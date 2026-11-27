import Foundation

/// NROOP: one physical strap can bank its samples under more than one device id (the registry's active
/// row, and the row the connected strap is attributed to, #1881). Scoring reads ONE owner per day, so a
/// night split across two ids was seen with a hole in it (or not at all) and read "no sleep".
///
/// These helpers let the per-day scan top the owner's streams up with the sibling ids' samples WITHOUT
/// ever double-counting: a sibling row is used only for a minute in which the owner has no heart-rate
/// sample at all, so wherever the owner already has data it stays exactly as it was. Real rows only, no
/// interpolation, no invented samples.
public enum SiblingStreamMerge {

    /// Whole minutes (unix minute index) in which the owner has at least one heart-rate sample.
    public static func coveredMinutes(ownerHrTs: [Int]) -> Set<Int> {
        var out = Set<Int>()
        out.reserveCapacity(ownerHrTs.count / 50 + 1)
        for ts in ownerHrTs { out.insert(Int((Double(ts) / 60.0).rounded(.down))) }
        return out
    }

    /// `owner` plus every sibling row whose minute is NOT in `covered`, ordered by timestamp. The owner's
    /// rows keep their relative order; a sibling row never replaces or sits beside an owner row of the
    /// same minute. With no usable sibling rows the result is `owner` itself, unchanged.
    public static func fill<T>(owner: [T], siblings: [[T]], covered: Set<Int>, ts: (T) -> Int) -> [T] {
        var extra: [T] = []
        for rows in siblings {
            for row in rows where !covered.contains(Int((Double(ts(row)) / 60.0).rounded(.down))) {
                extra.append(row)
            }
        }
        guard !extra.isEmpty else { return owner }
        let combined = owner + extra
        return combined.enumerated()
            .sorted { (ts($0.element), $0.offset) < (ts($1.element), $1.offset) }
            .map(\.element)
    }

    /// Device ids whose samples may complete `owner`'s day. Only when the owner itself is a WHOOP (a
    /// registered WHOOP row, or the legacy/unregistered strap ids); an Oura / Apple Watch / import owner
    /// is never topped up. Candidates are every registered WHOOP row (any status, since an archived row
    /// the strap is still attributed to is the case this exists for) plus ids that hold raw heart rate
    /// in the store. Excluded: registered non-WHOOP rows, import / activity-file rows, and the
    /// computed-scores namespace (`-noop`). Sorted for a deterministic order.
    public static func candidateIds(owner: String, registeredWhoop: [String], registeredOther: [String],
                                    storeIds: [String], legacyIds: [String]) -> [String] {
        let other = Set(registeredOther)
        let ownerIsWhoop = registeredWhoop.contains(owner)
            || (!other.contains(owner) && !owner.hasSuffix("-noop"))
        guard ownerIsWhoop, !other.contains(owner) else { return [] }
        var set = Set(registeredWhoop)
        for id in storeIds + legacyIds { set.insert(id) }
        return set.filter { $0 != owner && !other.contains($0) && !$0.hasSuffix("-noop") && !$0.isEmpty }.sorted()
    }
}
