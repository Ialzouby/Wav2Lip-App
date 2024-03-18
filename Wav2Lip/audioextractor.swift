import AVFoundation
import Foundation

class AudioExtractor {
    static func extractAudioAsWAV(from videoURL: URL, outputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let asset = AVURLAsset(url: videoURL)
        
      
        asset.loadTracks(withMediaType: .audio) { (tracksOrNil, error) in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let tracks = tracksOrNil, let audioTrack = tracks.first else {
                    completion(.failure(NSError(domain: "AudioExtractor", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio track found"])))
                    return
                }
                
                do {
                    let assetReader = try AVAssetReader(asset: asset)
                    let audioOutputSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsNonInterleaved: false,
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1
                    ]
                    
                    let assetReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioOutputSettings)
                    assetReader.add(assetReaderOutput)
                    
                    guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .wav) else {
                        completion(.failure(NSError(domain: "AudioExtractor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AVAssetWriter"])))
                        return
                    }
                    
                    let assetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
                    assetWriter.add(assetWriterInput)
                    
                    assetReader.startReading()
                    assetWriter.startWriting()
                    assetWriter.startSession(atSourceTime: CMTime.zero)
                    
                    let dispatchQueue = DispatchQueue(label: "audioExtractorQueue")
                    assetWriterInput.requestMediaDataWhenReady(on: dispatchQueue) {
                        while assetWriterInput.isReadyForMoreMediaData {
                            if let sampleBuffer = assetReaderOutput.copyNextSampleBuffer() {
                                assetWriterInput.append(sampleBuffer)
                            } else {
                                assetWriterInput.markAsFinished()
                                switch assetReader.status {
                                case .completed:
                                    assetWriter.finishWriting {
                                        completion(.success(outputURL))
                                    }
                                default:
                                    assetReader.cancelReading()
                                    assetWriter.cancelWriting()
                                    completion(.failure(NSError(domain: "AudioExtractor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to read/write audio data"])))
                                }
                                break
                            }
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
}
