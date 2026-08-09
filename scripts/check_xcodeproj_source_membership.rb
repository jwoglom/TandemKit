#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "set"

begin
  require "xcodeproj"
rescue LoadError
  warn "Missing Ruby gem 'xcodeproj'. Install it with:"
  warn "  gem install xcodeproj --no-document"
  exit 2
end

DEFAULTS = {
  project: "TandemKit.xcodeproj",
  target: nil,
  source_root: nil,
  mode: :check
}.freeze

# TandemKit.xcodeproj is a single-framework project: the SwiftPM targets
# TandemCore/TandemKit/TandemKitUI all compile into the one "TandemKit"
# framework target, so each of their source roots maps to it.
#
# There is no exclusion list. Every .swift file under a source root below, and
# every .swift file under every Tests/* directory, must be a member of the
# corresponding target -- that is what keeps a test from being silently absent
# from the CI run (which is how the TandemKitTests target ended up with an empty
# Sources build phase). A file that cannot compile has to be deleted or fixed,
# not hidden from the check.
SOURCE_TARGET_PAIRS = [
  { target: "TandemKit",       source_root: "Sources/TandemCore" },
  { target: "TandemKit",       source_root: "Sources/TandemKit" },
  { target: "TandemKit",       source_root: "Sources/TandemKitUI" },
  { target: "TandemKitPlugin", source_root: "Sources/TandemKitPlugin" },
].freeze

# Every directory under Tests/ is discovered at run time and mapped to this
# target, so adding a new test directory cannot bypass the check.
TEST_TARGET = "TandemKitTests"

def repo_root
  Pathname.new(__dir__).join("..").realpath
end

def normalize_path(path)
  File.realpath(path.to_s)
rescue StandardError
  path.to_s
end

def within_root?(path, root)
  path == root || path.start_with?("#{root}/")
end

def source_file_paths_under(root)
  Dir.glob(root.join("**/*.swift").to_s)
    .map { |p| normalize_path(p) }
    .sort
end

def relative_dirs_under(root, parent)
  Dir.glob(root.join(parent, "*").to_s)
    .select { |p| File.directory?(p) }
    .map { |p| Pathname.new(p).relative_path_from(root).to_s }
    .reject { |rel| Dir.glob(root.join(rel, "**/*.swift").to_s).empty? }
    .sort
end

# One pair per Tests/* directory, so a newly added test directory is checked
# without anyone having to remember to register it here.
def test_target_pairs(root)
  relative_dirs_under(root, "Tests").map do |rel|
    { target: TEST_TARGET, source_root: rel }
  end
end

# Source directories holding Swift files that no pair covers. These would be
# invisible to the membership check, so report them rather than skip them.
def unmapped_source_dirs(root)
  mapped = SOURCE_TARGET_PAIRS.map { |pair| pair[:source_root] }
  relative_dirs_under(root, "Sources").reject { |rel| mapped.include?(rel) }
end

def file_ref_abs_path(file_ref)
  return nil unless file_ref.respond_to?(:real_path)

  normalize_path(file_ref.real_path)
rescue StandardError
  nil
end

def project_file_refs_under_source_root(project, source_root_abs)
  project.files
    .map { |f| file_ref_abs_path(f) }
    .compact
    .select { |p| p.end_with?(".swift") && within_root?(p, source_root_abs) }
    .to_set
end

def target_source_file_refs_under_source_root(target, source_root_abs)
  target.source_build_phase.files_references
    .map { |f| file_ref_abs_path(f) }
    .compact
    .select { |p| p.end_with?(".swift") && within_root?(p, source_root_abs) }
    .to_set
end

def find_target!(project, target_name)
  project.targets.find { |t| t.name == target_name } ||
    abort(<<~MSG)
      Target not found in #{project.path}: #{target_name}
      Available targets: #{project.targets.map(&:name).sort.join(', ')}
      Update ALL_TARGET_SOURCE_PAIRS in #{File.basename(__FILE__)} if the project layout changed.
    MSG
end

def relpath_from_repo(abs_path)
  Pathname.new(abs_path).relative_path_from(repo_root).to_s
end

def find_project_file_ref(project, abs_path)
  abs_norm = normalize_path(abs_path)
  project.files.find { |f| file_ref_abs_path(f) == abs_norm }
end

def group_abs_path(group)
  return nil unless group.respond_to?(:real_path)

  normalize_path(group.real_path)
rescue StandardError
  nil
end

def find_group_for_abs_directory(project, abs_dir)
  abs_norm = normalize_path(abs_dir)
  project.groups.find { |g| group_abs_path(g) == abs_norm }
end

def ensure_file_ref!(project, abs_path)
  existing = find_project_file_ref(project, abs_path)
  return existing if existing

  rel = relpath_from_repo(abs_path)
  dir_abs = File.dirname(abs_path)
  file_name = File.basename(rel)
  if (group = find_group_for_abs_directory(project, dir_abs))
    group.files.find { |f| f.path == file_name } || group.new_file(file_name)
  else
    # Fallback: create a root-level reference using the repo-relative path.
    # This preserves a correct real_path even if an expected PBXGroup is missing.
    project.main_group.new_file(rel)
  end
end

def target_has_source_build_file?(target, file_ref)
  target.source_build_phase.files_references.any? { |f| f.uuid == file_ref.uuid }
end

def stale_broken_duplicate_swift_source_entries(target)
  entries = target.source_build_phase.files.map do |build_file|
    file_ref = build_file.file_ref
    next unless file_ref&.path

    ref_path = file_ref.path.to_s
    next unless ref_path.end_with?(".swift")

    abs = file_ref_abs_path(file_ref)
    {
      build_file: build_file,
      file_ref: file_ref,
      basename: File.basename(ref_path),
      abs: abs,
      exists: abs && File.file?(abs)
    }
  end.compact

  entries
    .group_by { |e| e[:basename] }
    .values
    .flat_map do |group|
      next [] unless group.length > 1
      next [] unless group.any? { |e| e[:exists] }

      group.select { |e| !e[:exists] }
    end
end

def source_build_target_owners(project, file_ref)
  project.targets.select do |target|
    target.respond_to?(:source_build_phase) &&
      target.source_build_phase &&
      target.source_build_phase.files_references.any? { |f| f.uuid == file_ref.uuid }
  end
end

def orphan_broken_duplicate_swift_file_refs(project)
  entries = project.files.map do |file_ref|
    next unless file_ref&.path

    ref_path = file_ref.path.to_s
    next unless ref_path.end_with?(".swift")

    abs = file_ref_abs_path(file_ref)
    {
      file_ref: file_ref,
      basename: File.basename(ref_path),
      abs: abs,
      exists: abs && File.file?(abs),
      source_owner_targets: source_build_target_owners(project, file_ref)
    }
  end.compact

  entries
    .group_by { |e| e[:basename] }
    .values
    .flat_map do |group|
      next [] unless group.length > 1
      next [] unless group.any? { |e| e[:exists] }

      group.select { |e| !e[:exists] && e[:source_owner_targets].empty? }
    end
end

def misplaced_group_file_refs(project, source_root_abs)
  misplaced = []

  project.files.each do |file_ref|
    next unless file_ref&.path
    ref_path = file_ref.path.to_s
    next unless ref_path.end_with?(".swift")

    abs = file_ref_abs_path(file_ref)
    next unless abs && within_root?(abs, source_root_abs)
    next unless File.file?(abs)

    expected_dir = File.dirname(abs)
    parent_group = file_ref.parent
    next unless parent_group.is_a?(Xcodeproj::Project::Object::PBXGroup)

    parent_abs = group_abs_path(parent_group)
    next if parent_abs && normalize_path(expected_dir) == parent_abs

    # File is in the wrong group
    correct_group = find_group_for_abs_directory(project, expected_dir)
    misplaced << {
      file_ref: file_ref,
      abs: abs,
      expected_dir: expected_dir,
      current_group: parent_group,
      correct_group: correct_group
    }
  end

  misplaced
end

def find_or_create_group_for_abs_directory(project, abs_dir, source_root_abs)
  existing = find_group_for_abs_directory(project, abs_dir)
  return existing if existing

  # Walk up to find the nearest existing parent group, then create children down
  parts = Pathname.new(abs_dir).relative_path_from(Pathname.new(source_root_abs)).to_s.split("/")

  # Find the source root group first
  source_root_group = find_group_for_abs_directory(project, source_root_abs)
  unless source_root_group
    # Try to find any ancestor group
    current_dir = source_root_abs
    project.groups.each do |g|
      gp = group_abs_path(g)
      next unless gp && current_dir.start_with?("#{gp}/")
      source_root_group = g
    end
  end

  return nil unless source_root_group

  # Walk down from the source root group creating subgroups as needed
  current_group = source_root_group
  current_path = source_root_abs

  parts.each do |part|
    current_path = File.join(current_path, part)
    child_group = current_group.children.find do |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.path == part
    end

    # `current_group.new_group` parents the child directly. Creating it via
    # `project.new_group` and appending would leave it owned by the main group
    # as well, and a double-parented group makes `real_path` unresolvable.
    child_group ||= current_group.new_group(part, part)

    current_group = child_group
  end

  current_group
end

def fix_misplaced_group_refs!(project, misplaced, source_root_abs)
  changed = false

  misplaced.each do |entry|
    correct_group = entry[:correct_group] ||
      find_or_create_group_for_abs_directory(project, entry[:expected_dir], source_root_abs)
    next unless correct_group

    file_ref = entry[:file_ref]
    current_group = entry[:current_group]

    # Remove from current group
    current_group.children.delete(file_ref)

    # Update path to be relative to the new group
    file_ref.path = File.basename(file_ref.path.to_s)
    file_ref.name = nil if file_ref.respond_to?(:name=)
    file_ref.source_tree = "<group>"

    # Add to correct group
    correct_group.children << file_ref
    changed = true
  end

  changed
end

def print_misplaced_groups(entries)
  return if entries.empty?

  fixable = entries.select { |e| e[:correct_group] }
  unfixable = entries.reject { |e| e[:correct_group] }

  unless fixable.empty?
    puts "  Misplaced file references (fixable): #{fixable.length}"
    fixable.each do |e|
      puts "    - #{File.basename(e[:abs])} (in #{e[:current_group].display_name}, should be #{e[:correct_group].display_name})"
    end
  end

  unless unfixable.empty?
    puts "  Misplaced file references (no matching group): #{unfixable.length}"
    unfixable.each do |e|
      puts "    - #{File.basename(e[:abs])} (in #{e[:current_group].display_name}, expected dir: #{relpath_from_repo(e[:expected_dir])})"
    end
  end
end

def print_stale_broken_duplicates(target_name, entries)
  return if entries.empty?

  puts "  Stale broken duplicate target source entries in #{target_name}: #{entries.length}"
  entries.each do |e|
    display = e[:abs] || e[:file_ref].path.to_s
    if display.start_with?(repo_root.to_s + "/")
      display = relpath_from_repo(display)
    end
    puts "    - #{e[:basename]} (#{display})"
  end
end

def print_orphan_broken_file_refs(entries)
  return if entries.empty?

  puts "  Orphan broken duplicate file references: #{entries.length}"
  entries.each do |e|
    display = e[:abs] || e[:file_ref].path.to_s
    if display.start_with?(repo_root.to_s + "/")
      display = relpath_from_repo(display)
    end
    puts "    - #{e[:basename]} (#{display})"
  end
end

def print_missing(header, paths)
  return if paths.empty?

  puts "  #{header}: #{paths.length}"
  paths.each do |abs|
    puts "    - #{relpath_from_repo(abs)}"
  end
end

def parse_args
  opts = DEFAULTS.dup

  OptionParser.new do |o|
    o.banner = "Usage: ruby scripts/check_xcodeproj_source_membership.rb [--check|--fix]"
    o.on("--check", "Check only (default)") { opts[:mode] = :check }
    o.on("--fix", "Add missing file references + target source entries") { opts[:mode] = :fix }
    o.on("--project PATH", "Xcode project path (default: #{DEFAULTS[:project]})") { |v| opts[:project] = v }
    o.on("--target NAME", "Target name (default: #{DEFAULTS[:target]})") { |v| opts[:target] = v }
    o.on("--source-root PATH", "Source directory to enforce (default: #{DEFAULTS[:source_root]})") { |v| opts[:source_root] = v }
    o.on("-h", "--help", "Show help") do
      puts o
      exit 0
    end
  end.parse!

  opts
end

def check_or_fix_pair(project, project_path, root, target_name, source_root_rel, mode)
  source_root = root.join(source_root_rel)
  return nil unless source_root.directory?

  target = find_target!(project, target_name)

  disk_files = source_file_paths_under(source_root)
  disk_set = disk_files.to_set
  project_set = project_file_refs_under_source_root(project, source_root.to_s)
  target_set = target_source_file_refs_under_source_root(target, source_root.to_s)

  missing_project_refs = (disk_set - project_set).to_a.sort
  missing_target_membership = (disk_set - target_set).to_a.sort
  stale_broken_duplicates = stale_broken_duplicate_swift_source_entries(target)
  orphan_broken_file_refs = orphan_broken_duplicate_swift_file_refs(project)
  misplaced_refs = misplaced_group_file_refs(project, source_root.to_s)

  puts "Target: #{target_name}  Source root: #{source_root_rel}  Swift files: #{disk_files.length}"

  has_issues = !missing_project_refs.empty? || !missing_target_membership.empty? ||
               !stale_broken_duplicates.empty? || !orphan_broken_file_refs.empty? ||
               !misplaced_refs.empty?

  if mode == :fix && has_issues
    changed = false

    missing_target_membership.each do |abs|
      file_ref = ensure_file_ref!(project, abs)
      next if target_has_source_build_file?(target, file_ref)

      target.source_build_phase.add_file_reference(file_ref, true)
      changed = true
    end

    stale_broken_duplicate_swift_source_entries(target).each do |entry|
      entry[:build_file].remove_from_project
      changed = true
    end

    orphan_broken_duplicate_swift_file_refs(project).each do |entry|
      entry[:file_ref].remove_from_project
      changed = true
    end

    # Re-detect misplaced refs after adding missing files (ensure_file_ref! may
    # have created new refs in the main group that now need relocating)
    misplaced_refs = misplaced_group_file_refs(project, source_root.to_s)

    if fix_misplaced_group_refs!(project, misplaced_refs, source_root.to_s)
      changed = true
    end

    if changed
      project.save
      project = Xcodeproj::Project.open(project_path.to_s)
      target = find_target!(project, target_name)
      project_set = project_file_refs_under_source_root(project, source_root.to_s)
      target_set = target_source_file_refs_under_source_root(target, source_root.to_s)
      missing_project_refs = (disk_set - project_set).to_a.sort
      missing_target_membership = (disk_set - target_set).to_a.sort
      stale_broken_duplicates = stale_broken_duplicate_swift_source_entries(target)
      orphan_broken_file_refs = orphan_broken_duplicate_swift_file_refs(project)
      misplaced_refs = misplaced_group_file_refs(project, source_root.to_s)
      puts "  Applied fixes"
    end
  end

  ok = missing_project_refs.empty? && missing_target_membership.empty? &&
       stale_broken_duplicates.empty? && orphan_broken_file_refs.empty? &&
       misplaced_refs.empty?

  if ok
    puts "  Status: OK"
  else
    puts "  Status: DRIFT DETECTED"
    print_missing("Missing file references in project", missing_project_refs)
    print_missing("Missing target source membership in #{target_name}", missing_target_membership)
    print_stale_broken_duplicates(target_name, stale_broken_duplicates)
    print_orphan_broken_file_refs(orphan_broken_file_refs)
    print_misplaced_groups(misplaced_refs)
  end

  { ok: ok, project: project }
end

opts = parse_args
root = repo_root
project_path = root.join(opts[:project])

abort("Project not found: #{project_path}") unless project_path.exist?

project = Xcodeproj::Project.open(project_path.to_s)

explicit_pair = opts[:target] && opts[:source_root]
pairs = if explicit_pair
          [{ target: opts[:target], source_root: opts[:source_root] }]
        else
          SOURCE_TARGET_PAIRS + test_target_pairs(root)
        end

puts "Project: #{opts[:project]}"
any_failed = false

pairs.each do |pair|
  result = check_or_fix_pair(project, project_path, root, pair[:target], pair[:source_root], opts[:mode])
  next unless result

  project = result[:project]
  any_failed = true unless result[:ok]
end

# A source directory nobody maps to a target would never be checked at all --
# the same blind spot the removed exclusion list used to create, one level up.
unless explicit_pair
  unmapped = unmapped_source_dirs(root)
  unless unmapped.empty?
    puts
    puts "Unmapped source directories containing Swift files: #{unmapped.length}"
    unmapped.each { |rel| puts "  - #{rel}" }
    puts "  Add each to SOURCE_TARGET_PAIRS in #{File.basename(__FILE__)} (or delete the directory)."
    any_failed = true
  end
end

if any_failed
  puts
  puts "Remediation:"
  puts "  ruby scripts/check_xcodeproj_source_membership.rb --fix"
  puts "  (unmapped source directories must be registered by hand)"
  exit 1
end
