import Foundation
import CoreGraphics

/// A single TV workspace: a persistent navigation rail, with media below it.
enum TVSessionLayout {
    static func railHeight(_ screen: CGRect) -> CGFloat { min(108,max(82,screen.width/20)) }
    static func stage(_ screen: CGRect) -> CGRect {
        let margin:CGFloat=14
        return CGRect(x:screen.minX+margin,y:screen.minY+margin,width:max(1,screen.width-margin*2),height:max(1,screen.height-railHeight(screen)-margin*2))
    }
    static func frames(in stage:CGRect,count:Int) -> [CGRect] {
        guard (1...4).contains(count) else { return [] }
        if count==1 { return [stage] }
        let gap:CGFloat=12,w=(stage.width-gap)/2,h=(stage.height-gap)/2
        if count==2 { return [CGRect(x:stage.minX,y:stage.minY,width:w,height:stage.height),CGRect(x:stage.minX+w+gap,y:stage.minY,width:w,height:stage.height)] }
        if count==3 { return [CGRect(x:stage.minX,y:stage.minY,width:w,height:stage.height),CGRect(x:stage.minX+w+gap,y:stage.minY+h+gap,width:w,height:h),CGRect(x:stage.minX+w+gap,y:stage.minY,width:w,height:h)] }
        return [CGRect(x:stage.minX,y:stage.minY+h+gap,width:w,height:h),CGRect(x:stage.minX+w+gap,y:stage.minY+h+gap,width:w,height:h),CGRect(x:stage.minX,y:stage.minY,width:w,height:h),CGRect(x:stage.minX+w+gap,y:stage.minY,width:w,height:h)]
    }
    /// A running game keeps the large left area as a 16:9 window; up to three services stack beside it, top first.
    static func gameFrames(in stage:CGRect,media:Int) -> (game:CGRect,media:[CGRect]) {
        let gap:CGFloat=12,count=max(0,min(media,3))
        let area=count==0 ? stage:CGRect(x:stage.minX,y:stage.minY,width:(stage.width-gap)*0.62,height:stage.height)
        let w=min(area.width,area.height*16/9),h=w*9/16
        let game=CGRect(x:area.minX+(area.width-w)/2,y:area.minY+(area.height-h)/2,width:w,height:h).integral
        guard count>0 else{return(game,[])}
        let x:CGFloat=area.maxX+gap,width:CGFloat=stage.maxX-x,n=CGFloat(count)
        let height:CGFloat=(stage.height-gap*(n-1))/n
        let column:[CGRect]=(0..<count).map{i in
            let k=CGFloat(i)
            let y:CGFloat=stage.maxY-height*(k+1)-gap*k
            return CGRect(x:x,y:y,width:width,height:height).integral
        }
        return(game,column)
    }
}
