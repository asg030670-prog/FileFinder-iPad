// On Apple platforms view models use Combine's `ObservableObject` / `@Published` so SwiftUI can
// observe them. On other platforms (e.g. Linux CI) Combine is not available, so minimal
// stand-ins are provided, which allows the view model logic to be compiled and unit tested anywhere.
#if !canImport(Combine)
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}
#endif
