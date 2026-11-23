/// One positional change to a list the SDK keeps in step with ours (its `VectorDiff`), mirrored without the SDK so
/// the translation can be tested.
public enum ListDiff<Element> {
    case append([Element])
    case clear
    case pushFront(Element)
    case pushBack(Element)
    case popFront
    case popBack
    case insert(Int, Element)
    case set(Int, Element)
    case remove(Int)
    case truncate(Int)
    case reset([Element])
}

/// What a batch of diffs did besides changing the list.
public struct ListDiffOutcome: Equatable, Sendable {
    /// A `clear` or `reset` replaced everything that was there: what was loaded before is gone.
    public var dropped = false
    /// Diffs that pointed past the end of our copy, so it no longer matches the SDK's; they are skipped.
    public var outOfRange = 0
    public init(dropped: Bool = false, outOfRange: Int = 0) { self.dropped = dropped; self.outOfRange = outOfRange }
}

extension Array {
    /// Applies the diffs in the order they were sent.
    @discardableResult
    public mutating func apply(_ diffs: [ListDiff<Element>]) -> ListDiffOutcome {
        var out = ListDiffOutcome()
        for d in diffs {
            switch d {
            case .append(let v): self += v
            case .clear: removeAll(); out.dropped = true
            case .pushFront(let v): insert(v, at: 0)
            case .pushBack(let v): append(v)
            case .popFront: if !isEmpty { removeFirst() }
            case .popBack: if !isEmpty { removeLast() }
            case .insert(let i, let v): if i >= 0, i <= count { insert(v, at: i) } else { out.outOfRange += 1 }
            case .set(let i, let v): if indices.contains(i) { self[i] = v } else { out.outOfRange += 1 }
            case .remove(let i): if indices.contains(i) { remove(at: i) } else { out.outOfRange += 1 }
            case .truncate(let n): self = Array(prefix(Swift.max(0, n)))
            case .reset(let v): self = v; out.dropped = true
            }
        }
        return out
    }
}
