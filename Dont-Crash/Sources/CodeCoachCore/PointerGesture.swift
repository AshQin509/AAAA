import Foundation

/// Classifies the whole gesture, not the final window displacement.
public struct PointerGesture {
    public enum Result { case none, click, drag }
    public private(set) var start: CGPoint?
    public private(set) var dragging = false
    public let threshold: CGFloat
    public init(threshold: CGFloat = 4) { self.threshold=threshold }
    public mutating func begin(at point: CGPoint) { start=point; dragging=false }
    public mutating func update(at point: CGPoint) {
        guard let start else { return }
        if hypot(point.x-start.x,point.y-start.y) >= threshold { dragging=true }
    }
    public mutating func end(at point: CGPoint) -> Result {
        guard start != nil else { return .none }
        update(at:point)
        let result:Result=dragging ? .drag:.click
        start=nil; dragging=false
        return result
    }
}
