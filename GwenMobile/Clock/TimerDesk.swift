import Foundation

@MainActor
final class TimerDesk: ObservableObject {
    private(set) var setter: any TimerSetting
    #if DEBUG
    private var standIn = DeskStandIn<any TimerSetting>()
    #endif

    init(setter: any TimerSetting = TimerSetterPort.current) {
        self.setter = setter
    }

    #if DEBUG
    func stand(in setter: any TimerSetting) {
        standIn.stand(setter, over: &self.setter)
    }

    func restore() {
        standIn.restore(&setter)
    }
    #endif
}
