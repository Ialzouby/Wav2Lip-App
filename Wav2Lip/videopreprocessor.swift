//
//  videopreprocessor.swift
//  Wav2Lip
//
//  Created by Issam Alzouby on 2/9/24.
//

import Foundation
import AVFoundation
import CoreImage
import UIKit
import CoreML // Import CoreML for MLMultiArray

import Vision
import AVFoundation

class VideoPreprocessor {
    static func convertMOVToMP4(sourceURL: URL, outputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let asset = AVURLAsset(url: sourceURL, options: nil)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(NSError(domain: "VideoPreprocessor", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not create AVAssetExportSession"])))
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                completion(.success(outputURL))
            case .failed:
                if let error = exportSession.error {
                    completion(.failure(error))
                } else {
                    completion(.failure(NSError(domain: "VideoPreprocessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown failure"])))
                }
            case .cancelled:
                completion(.failure(NSError(domain: "VideoPreprocessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Export cancelled"])))
            default:
                break
            }
        }
    }
    
    func processVideoFrames(from videoURL: URL, completion: @escaping (Result<MLMultiArray, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: videoURL)
            guard let assetTrack = asset.tracks(withMediaType: .video).first,
                  let assetReader = try? AVAssetReader(asset: asset) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "VideoPreprocessor", code: 0, userInfo: [NSLocalizedDescriptionKey: "Initialization failed."])))
                }
                return
            }

            let trackOutput = AVAssetReaderTrackOutput(track: assetTrack, outputSettings: [String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_32BGRA)])
            assetReader.add(trackOutput)
            guard assetReader.startReading() else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "VideoPreprocessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reading failed."])))
                }
                return
            }

            var selectedFrames = [UIImage]()
            let totalFrames = 6
            var frameCount = 0

            while let sampleBuffer = trackOutput.copyNextSampleBuffer(), selectedFrames.count < totalFrames {
                if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                    if frameCount % (Int(assetTrack.nominalFrameRate) / totalFrames) == 0 {
                        if let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) {
                            let uiImage = UIImage(cgImage: cgImage).resizeImage(targetSize: CGSize(width: 96, height: 96))
                            selectedFrames.append(uiImage)
                        }
                    }
                    frameCount += 1
                }
            }

            do {
                let multiArray = try self.framesToMultiArray(frames: selectedFrames)
                DispatchQueue.main.async {
                    completion(.success(multiArray))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func framesToMultiArray(frames: [UIImage]) throws -> MLMultiArray {
        // Ensure the MLMultiArray has the correct shape
        let multiArray = try MLMultiArray(shape: [1, 1, 6, 96, 96], dataType: .float32)
        
        for (index, frame) in frames.enumerated() {
            // Verify each frame is 96x96
            guard frame.size == CGSize(width: 96, height: 96) else {
                throw NSError(domain: "VideoPreprocessorError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Frame size is not 96x96 pixels."])
            }
            
            // Extract pixel data safely
            guard let pixelData = frame.pixelData(), pixelData.count == 96 * 96 * 4 else {
                throw NSError(domain: "VideoPreprocessorError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unexpected pixel data size or format."])
            }
            
            for y in 0..<96 {
                for x in 0..<96 {
                    let pixelIndex = (y * 96 + x) * 4
                    // Safely access pixel data to prevent out-of-range errors
                    guard pixelIndex < pixelData.count - 4 else {
                        throw NSError(domain: "VideoPreprocessorError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Pixel index out of bounds."])
                    }
                    // Assuming grayscale, so taking the red channel only and normalize pixel values
                    let pixelValue = Float(pixelData[pixelIndex]) / 255.0
                    multiArray[[0, 0, index, y, x] as [NSNumber]] = NSNumber(value: pixelValue)
                }
            }
        }
        return multiArray
    }
}

extension UIImage {
    func resizeImage(targetSize: CGSize) -> UIImage {
        let size = self.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: rect)
        guard let newImage = UIGraphicsGetImageFromCurrentImageContext() else { return self }
        UIGraphicsEndImageContext()
        return newImage
    }

    func pixelData() -> [UInt8]? {
        let size = self.size
        let dataSize = size.width * size.height * 4
        var pixelData = [UInt8](repeating: 0, count: Int(dataSize))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &pixelData,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 4 * Int(size.width),
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let cgImage = self.cgImage else { return nil }
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return pixelData
    }
}

// Assuming you have a URL to a .mov file and an output URL for the .mp4 file
//let sourceURL: URL = ... // Your source .mov URL
//let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//let outputURL = documentsDirectory.appendingPathComponent("output.mp4")

//VideoPreprocessor.convertMOVToMP4(sourceURL: sourceURL, outputURL: outputURL) { result in
  //  DispatchQueue.main.async {
    //    switch result {
     //   case .success(let url):
      //      print("Video converted successfully: \(url)")
        // Update your UI or proceed with the next step here
      //  case .failure(let error):
      //      print("Video conversion failed: \(error.localizedDescription)")
            // Handle error
   //     }
 //   }
//}


func extractAndResizeFrames(from videoURL: URL, targetSize: CGSize, completion: @escaping ([UIImage]) -> Void) {
    // Create an AVAsset and AVAssetImageGenerator
    let asset = AVAsset(url: videoURL)
    let assetImgGenerate = AVAssetImageGenerator(asset: asset)
    assetImgGenerate.appliesPreferredTrackTransform = true
    assetImgGenerate.requestedTimeToleranceAfter = .zero
    assetImgGenerate.requestedTimeToleranceBefore = .zero

    // Calculate the duration of the video
    let duration = asset.duration
    let durationInSeconds = CMTimeGetSeconds(duration)
    let frameInterval = Float64(1) // Change this value to extract more or fewer frames
    
    var times = [NSValue]()
    var currentTime = Float64(0)
    while currentTime < durationInSeconds {
        let cmTime = CMTimeMakeWithSeconds(currentTime, preferredTimescale: duration.timescale)
        times.append(NSValue(time: cmTime))
        currentTime += frameInterval
    }
    
    // Extracting frames
    var extractedImages = [UIImage]()
    var imagesCount = times.count
    for time in times {
        assetImgGenerate.generateCGImagesAsynchronously(forTimes: [time]) { _, image, _, _, _ in
            if let image = image {
                let uiImage = UIImage(cgImage: image)
                // Resize image
                let resizedImage = resizeImage(image: uiImage, targetSize: targetSize)
                extractedImages.append(resizedImage)
            }
            imagesCount -= 1
            if imagesCount == 0 {
                completion(extractedImages)
            }
        }
    }
}

// Image resizing function
func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
    let size = image.size
    
    let widthRatio  = targetSize.width  / size.width
    let heightRatio = targetSize.height / size.height
    
    // Figure out what our orientation is, and use that to form the rectangle
    var newSize: CGSize
    if(widthRatio > heightRatio) {
        newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
    } else {
        newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
    }
    
    // This is the rect that we've calculated out and this is what is actually used below
    let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
    
    // Actually do the resizing to the rect using the ImageContext stuff
    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: rect)
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return newImage ?? UIImage()
}


func pixelBuffer(from image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
    let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
    guard status == kCVReturnSuccess else {
        return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
    let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

    context?.translateBy(x: 0, y: CGFloat(height))
    context?.scaleBy(x: 1.0, y: -1.0)

    UIGraphicsPushContext(context!)
    image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
    UIGraphicsPopContext()
    CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

    return pixelBuffer
}


// Assuming you have a method to extract frames from the video and store them in an array
// Let's preprocess these frames to match the model's input

func preprocessVideoFrames(frames: [UIImage]) -> MLMultiArray? {
    let sequenceLength = 6 // The number of frames to use
    let batchSize = 1
    let channels = 1 // Grayscale, change this if your model expects RGB
    let height = 96
    let width = 96
    
    guard let multiArray = try? MLMultiArray(shape: [NSNumber(value: sequenceLength), NSNumber(value: batchSize), NSNumber(value: channels), NSNumber(value: height), NSNumber(value: width)], dataType: .float32) else {
        print("Error creating MLMultiArray")
        return nil
    }
    
    for (index, frame) in frames.prefix(sequenceLength).enumerated() {
        let resizedImage = resizeImage(image: frame, targetSize: CGSize(width: width, height: height))
        if let pixelBuffer = pixelBuffer(from: resizedImage, width: width, height: height) {
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let buffer = baseAddress!.assumingMemoryBound(to: UInt8.self)

            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * 4 // Assuming BGRA format
                    let b = Float(buffer[pixelIndex]) / 255.0
                    let g = Float(buffer[pixelIndex+1]) / 255.0
                    let r = Float(buffer[pixelIndex+2]) / 255.0
                    let pixelValue = (r + g + b) / 3.0 // Convert to grayscale by averaging the RGB components
                    multiArray[[0, 0, index, y, x] as [NSNumber]] = NSNumber(value: pixelValue)
                }
            }

            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        }
    }

    
    return multiArray
}

// Add methods for resizing images and converting UIImage to CVPixelBuffer if needed
