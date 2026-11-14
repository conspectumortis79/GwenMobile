import Foundation

@MainActor
final class ReminderDesk: ObservableObject {
    private(set) var store: any ReminderStoring
    private(set) var places: any ReminderPlaceLooking
    #if DEBUG
    private var storeStandIn = DeskStandIn<any ReminderStoring>()
    private var placesStandIn = DeskStandIn<any ReminderPlaceLooking>()
    #endif

    init(store: any ReminderStoring = EventKitReminderStore(),
         places: any ReminderPlaceLooking = ReminderPlacePort.current) {
        self.store = store
        self.places = places
    }

    func runner() -> ReminderFlowRunner {
        ReminderFlowRunner(store: store, places: places)
    }

    #if DEBUG
    func stand(in store: any ReminderStoring, places: any ReminderPlaceLooking? = nil) {
        storeStandIn.stand(store, over: &self.store)
        if let places { placesStandIn.stand(places, over: &self.places) }
    }

    func restore() {
        storeStandIn.restore(&store)
        placesStandIn.restore(&places)
    }
    #endif
}
