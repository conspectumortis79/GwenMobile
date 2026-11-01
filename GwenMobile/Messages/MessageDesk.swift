import Foundation

@MainActor
final class MessageDesk: ObservableObject {
    private(set) var directory: any ContactDirectory
    private(set) var sender: any MessageSending
    private(set) var reviewer: any MessageSending
    #if DEBUG
    private var senderStandIn = DeskStandIn<any MessageSending>()
    private var reviewerStandIn = DeskStandIn<any MessageSending>()
    private var directoryStandIn = DeskStandIn<any ContactDirectory>()
    #endif

    init(directory: any ContactDirectory = LiveContactDirectory(), sender: (any MessageSending)? = nil,
         reviewer: (any MessageSending)? = nil) {
        self.directory = directory
        self.sender = sender ?? MessagingChoice.sender(for: MessagingChoice.current())
        self.reviewer = reviewer ?? MessageSenderPort.compose()
    }

    func runner() -> MessageFlowRunner {
        MessageFlowRunner(directory: directory, sender: sender, reviewer: reviewer)
    }

    #if DEBUG
    func stand(in sender: any MessageSending, directory: (any ContactDirectory)? = nil) {
        senderStandIn.stand(sender, over: &self.sender)
        reviewerStandIn.stand(sender, over: &self.reviewer)
        if let directory { directoryStandIn.stand(directory, over: &self.directory) }
    }

    func restore() {
        senderStandIn.restore(&sender)
        reviewerStandIn.restore(&reviewer)
        directoryStandIn.restore(&directory)
    }
    #endif
}
