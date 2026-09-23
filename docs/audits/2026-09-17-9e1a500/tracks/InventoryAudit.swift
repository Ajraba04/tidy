import Foundation
import TidyCore
let inventory: [String: Any] = [
 "catalog": CleanCatalog.allItems.map { ["id":$0.id,"title":$0.title,"mutationDenied":CapabilityRegistry.denialReason(for:$0.action,itemID:$0.id) != nil] as [String:Any] },
 "registry": PolicyDefaults.rows.map { $0.id.rawValue },
 "hardLimits": Dictionary(uniqueKeysWithValues:PolicyDefaults.hardLimits.map { ($0.key.rawValue,$0.value) })
]
print(String(data:try JSONSerialization.data(withJSONObject:inventory,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
