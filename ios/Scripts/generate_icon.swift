import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let out = CommandLine.arguments[1]
let context = CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red:0.11,green:0.29,blue:0.24,alpha:1)); context.fill(CGRect(x:0,y:0,width:1024,height:1024))
context.setStrokeColor(CGColor(red:0.96,green:0.94,blue:0.86,alpha:0.12)); context.setLineWidth(2)
for x in stride(from:128,through:1024,by:128) { context.move(to:CGPoint(x:x,y:0)); context.addLine(to:CGPoint(x:x,y:1024)); context.strokePath() }
for y in stride(from:128,through:1024,by:128) { context.move(to:CGPoint(x:0,y:y)); context.addLine(to:CGPoint(x:1024,y:y)); context.strokePath() }
context.setStrokeColor(CGColor(red:0.96,green:0.94,blue:0.86,alpha:1)); context.setLineWidth(56); context.setLineCap(.round)
context.move(to:CGPoint(x:270,y:285)); context.addCurve(to:CGPoint(x:705,y:700),control1:CGPoint(x:220,y:730),control2:CGPoint(x:820,y:170)); context.strokePath()
context.setFillColor(CGColor(red:0.96,green:0.94,blue:0.86,alpha:1)); context.fillEllipse(in:CGRect(x:201,y:216,width:138,height:138))
context.setFillColor(CGColor(red:0.87,green:0.48,blue:0.28,alpha:1)); context.fillEllipse(in:CGRect(x:618,y:613,width:174,height:174))
context.setFillColor(CGColor(red:0.96,green:0.94,blue:0.86,alpha:1)); context.fillEllipse(in:CGRect(x:678,y:673,width:54,height:54))
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath:out) as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(destination,context.makeImage()!,nil)
assert(CGImageDestinationFinalize(destination))
