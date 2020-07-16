import Foundation

enum CallError: Error {
    
    case busy
    case invalidUUID(uuid: String)
    case invalidSdp(sdp: String?)
    case missingUser(userId: String)
    case networkFailure
    case microphonePermissionDenied
    case inconsistentCallStarted
    
    case setRemoteSdp(Error)
    case answerConstruction(Error?)
    case setRemoteAnswer(Error)
    case clientFailure
    case offerConstruction(Error?)
    
    case invalidKrakenResponse
    case roomFull
    case remoteError(Int)
    
    case manuallyInitiated
    
    var alertContent: String {
        switch self {
        case .busy:
            return R.string.localizable.call_hint_on_another_call()
        case .networkFailure:
            return R.string.localizable.call_no_network()
        case .microphonePermissionDenied:
            return R.string.localizable.call_no_microphone_permission()
        case .roomFull:
            return R.string.localizable.group_call_room_full()
        default:
            return R.string.localizable.chat_message_call_failed()
        }
    }
    
}
