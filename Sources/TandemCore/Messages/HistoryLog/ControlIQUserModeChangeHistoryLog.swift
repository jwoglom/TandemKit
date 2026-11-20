//
//  ControlIQUserModeChangeHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's ControlIQUserModeChangeHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/ControlIQUserModeChangeHistoryLog.java
//
import Foundation

/// History log entry indicating a ControlIQ user mode change.
public class ControlIQUserModeChangeHistoryLog: HistoryLog {
    public static let typeId = 229

    public let currentUserMode: Int
    public let previousUserMode: Int
    public let requestedActionRaw: Int
    public let sleepStartedByGuiRaw: Int
    public let activeSleepSchedule: Int
    public let exerciseStoppedByTimerRaw: Int
    public let exerciseChoiceRaw: Int
    public let exerciseTime: Int
    public let eatingSoonStoppedByTimerRaw: Int

    public enum UserMode: Int {
        case normal = 0
        case sleeping = 1
        case exercising = 2
        case eatingSoon = 3
    }

    public enum RequestedAction: Int {
        case noUserRequest = 0
        case startSleep = 1
        case stopSleep = 2
        case startExercise = 3
        case stopExercise = 4
        case stopAll = 5
        case startEatingSoon = 6
        case stopEatingSoon = 7
    }

    public enum ExerciseChoice: Int {
        case continuous = 0
        case timed = 1
    }

    public var currentUserModeEnum: UserMode? {
        UserMode(rawValue: currentUserMode)
    }

    public var previousUserModeEnum: UserMode? {
        UserMode(rawValue: previousUserMode)
    }

    public var requestedAction: RequestedAction? {
        RequestedAction(rawValue: requestedActionRaw)
    }

    /// True if the currently-active sleep activity was started manually via the pump GUI,
    /// rather than by a scheduled sleep-activity time.
    public var isSleepStartedByGui: Bool {
        sleepStartedByGuiRaw != 0
    }

    /// True if the currently-active (or just-ended) exercise activity was stopped automatically
    /// by its configured timer, rather than manually via the pump GUI.
    public var isExerciseStoppedByTimer: Bool {
        exerciseStoppedByTimerRaw != 0
    }

    public var exerciseChoice: ExerciseChoice? {
        ExerciseChoice(rawValue: exerciseChoiceRaw)
    }

    /// True if the currently-active (or just-ended) eating-soon activity was stopped
    /// automatically by its configured timer, rather than manually via the pump GUI.
    public var isEatingSoonStoppedByTimer: Bool {
        eatingSoonStoppedByTimerRaw != 0
    }

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        currentUserMode = Int(raw[10])
        previousUserMode = Int(raw[11])
        requestedActionRaw = Int(raw[12])
        sleepStartedByGuiRaw = Int(raw[14])
        activeSleepSchedule = Int(raw[15])
        exerciseStoppedByTimerRaw = Int(raw[18])
        exerciseChoiceRaw = Int(raw[19])
        exerciseTime = Bytes.readShort(raw, 20)
        eatingSoonStoppedByTimerRaw = Int(raw[22])
        super.init(cargo: raw)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentUserMode: Int,
        previousUserMode: Int,
        requestedAction: Int,
        sleepStartedByGui: Int,
        activeSleepSchedule: Int,
        exerciseStoppedByTimer: Int,
        exerciseChoice: Int,
        exerciseTime: Int,
        eatingSoonStoppedByTimer: Int
    ) {
        let payload = ControlIQUserModeChangeHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentUserMode: currentUserMode,
            previousUserMode: previousUserMode,
            requestedAction: requestedAction,
            sleepStartedByGui: sleepStartedByGui,
            activeSleepSchedule: activeSleepSchedule,
            exerciseStoppedByTimer: exerciseStoppedByTimer,
            exerciseChoice: exerciseChoice,
            exerciseTime: exerciseTime,
            eatingSoonStoppedByTimer: eatingSoonStoppedByTimer
        )
        self.currentUserMode = currentUserMode
        self.previousUserMode = previousUserMode
        self.requestedActionRaw = requestedAction
        self.sleepStartedByGuiRaw = sleepStartedByGui
        self.activeSleepSchedule = activeSleepSchedule
        self.exerciseStoppedByTimerRaw = exerciseStoppedByTimer
        self.exerciseChoiceRaw = exerciseChoice
        self.exerciseTime = exerciseTime
        self.eatingSoonStoppedByTimerRaw = eatingSoonStoppedByTimer
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentUserMode: Int,
        previousUserMode: Int,
        requestedAction: Int,
        sleepStartedByGui: Int,
        activeSleepSchedule: Int,
        exerciseStoppedByTimer: Int,
        exerciseChoice: Int,
        exerciseTime: Int,
        eatingSoonStoppedByTimer: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(currentUserMode & 0xFF)]),
                Data([UInt8(previousUserMode & 0xFF)]),
                Data([UInt8(requestedAction & 0xFF)]),
                Bytes.emptyBytes(1),
                Data([UInt8(sleepStartedByGui & 0xFF)]),
                Data([UInt8(activeSleepSchedule & 0xFF)]),
                Bytes.emptyBytes(2),
                Data([UInt8(exerciseStoppedByTimer & 0xFF)]),
                Data([UInt8(exerciseChoice & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(exerciseTime),
                Data([UInt8(eatingSoonStoppedByTimer & 0xFF)])
            )
        )
    }

    override public var description: String {
        "ControlIQUserModeChangeHistoryLog(cargo=\(cargo.hexadecimalString), currentUserMode=\(currentUserMode), previousUserMode=\(previousUserMode), requestedActionRaw=\(requestedActionRaw), sleepStartedByGuiRaw=\(sleepStartedByGuiRaw), activeSleepSchedule=\(activeSleepSchedule), exerciseStoppedByTimerRaw=\(exerciseStoppedByTimerRaw), exerciseChoiceRaw=\(exerciseChoiceRaw), exerciseTime=\(exerciseTime), eatingSoonStoppedByTimerRaw=\(eatingSoonStoppedByTimerRaw))"
    }
}
