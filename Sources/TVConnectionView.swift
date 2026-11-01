import SwiftUI

struct TVConnectionView:View {
    @ObservedObject var tv:TVMode
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Label("Your TV connection",systemImage:"cable.connector").font(.system(size:17,weight:.semibold,design:.rounded))
            Toggle("Start TV when \(tv.automaticTVName) connects",isOn:$tv.automaticTVEnabled).toggleStyle(.switch)
            Toggle("Blank Mac screen on this TV",isOn:$tv.automaticallyBlankMac).toggleStyle(.switch)
            if tv.canBlankMac {Button{tv.setMacScreenBlank(!tv.macScreenBlanked)}label:{Label(tv.macScreenBlanked ? "Show Mac screen":"Blank Mac screen",systemImage:tv.macScreenBlanked ? "display":"display.trianglebadge.exclamationmark")}.buttonStyle(TVSoftButton())}
            if tv.active,!tv.targetIsBuiltIn,!tv.onAutomaticTV {Button("Use this display for automatic TV"){do{try tv.rememberCurrentTV()}catch{tv.lastError=true;tv.message=error.localizedDescription}}.buttonStyle(TVSoftButton())}
            Text("Click the black Mac screen or use Show Mac screen on your iPhone to reveal it. Ending TV or unplugging the TV restores it.").font(.system(size:12)).foregroundColor(TVStyle.muted).fixedSize(horizontal:false,vertical:true)
        }.font(.system(size:13)).tint(TVStyle.mint)
    }
}
