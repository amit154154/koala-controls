import AppKit
@main struct PublicDefaultsRegression {
 @MainActor static func main() {
  let settings=PadSettings.defaults()
  precondition(settings.vendorID==nil && settings.productID==nil && settings.deviceName==nil)
  for key in 1...12 {precondition(settings.mapping("k\(key)").action != nil);precondition(settings.mapping("k\(key)").source==nil)}
  precondition(settings.mapping("k9").action?.id=="win_min")
  precondition(settings.mapping("k11").action?.id=="win_max")
  let laptop=LaptopPlan.build(settings)
  precondition(laptop.count==11)
  precondition(laptop.first(where:{$0.key=="7"})?.control=="k8")
  for player in [false,true] {
   precondition(AdventureRules.level(-100,player:player)==1)
   for level in 2...100 {
    let threshold=AdventureRules.threshold(level,player:player)
    precondition(AdventureRules.level(threshold,player:player)==level)
    precondition(AdventureRules.level(threshold-1,player:player)==level-1)
   }
  }
  print("Public starter defaults and exact player/function level boundaries passed.")
 }
}
