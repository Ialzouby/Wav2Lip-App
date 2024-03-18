import SwiftUI
import AVFoundation
import Accelerate



struct ContentView: View {
    @State private var videoURLForAudio: URL?
    @State private var videoURLForVideo: URL?
    @State private var showingVideoPickerForAudio = false
    @State private var showingVideoPickerForVideo = false
    @State private var audioProcessingStatus: ProcessingStatus?
    @State private var videoProcessingStatus: ProcessingStatus?
    
    enum ProcessingStatus {
        case success(String)
        case failure(String)
        case processing 
    }
    
    var body: some View {
        VStack {
            Group {
                if let videoURLForAudio = videoURLForAudio {
                    Text("Selected Audio Video: \(videoURLForAudio.lastPathComponent)")
                        .font(.headline)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                    if audioProcessingStatus == nil {
                        styledButton(text: "Process Video for Audio", action: {
                            preprocessAndExtractAudio(from: videoURLForAudio)
                        })
                    } else {
                        statusMessage(audioProcessingStatus)
                    }
                } else {
                    styledButton(text: "Select Video for Audio", action: {
                        showingVideoPickerForAudio = true
                    })
                }
            }
            .padding(.bottom)
            
            Group {
                if let videoURLForVideo = videoURLForVideo {
                    Text("Selected Content Video: \(videoURLForVideo.lastPathComponent)")
                        .font(.headline)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                    if videoProcessingStatus == nil {
                        styledButton(text: "Process Video for Video", action: {
                            preprocessVideo(from: videoURLForVideo)
                        })
                    } else {
                        statusMessage(videoProcessingStatus)
                    }
                } else if audioProcessingStatus?.isSuccess == true {
                    styledButton(text: "Select Video for Video", action: {
                        showingVideoPickerForVideo = true
                    })
                }
            }
        }
        .sheet(isPresented: $showingVideoPickerForAudio) {
            VideoPicker(selectedVideoURL: $videoURLForAudio)
        }
        .sheet(isPresented: $showingVideoPickerForVideo) {
            VideoPicker(selectedVideoURL: $videoURLForVideo)
        }
    }
    
    private func styledButton(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(10)
        }
        .padding(.horizontal)
    }
    
    private func statusMessage(_ status: ProcessingStatus?) -> some View {
        Group {
            switch status {
            case .success(let message):
                Text(message)
                    .foregroundColor(.green)
                    .padding()
            case .failure(let message):
                Text(message)
                    .foregroundColor(.red)
                    .padding()
            case .processing:
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Processing...")
                }
                .padding()
            case .none:
                EmptyView()
            }
        }
        .transition(.opacity)
       
    }
    
    private var audioProcessingStatusMessage: String {
        switch audioProcessingStatus {
        case .success(let path):
            return "Audio processing successful: \(path)"
        case .failure(let message):
            return "Audio processing failed: \(message)"
        case .processing:
            return "Processing audio..."
        case .none:
            return ""
        }
    }
    
    private var videoProcessingStatusMessage: String {
        switch videoProcessingStatus {
        case .success(let path):
            return "Video processing successful: \(path)"
        case .failure(let message):
            return "Video processing failed: \(message)"
        case .processing:
            return "Processing video..."
        case .none:
            return ""
        }
    }
    
    private func preprocessAndExtractAudio(from videoURL: URL) {
        // Set the audio session category
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up the audio session: \(error)")
            self.audioProcessingStatus = .failure("Failed to set up the audio session.")
            return
        }

        // Update the processing status
        audioProcessingStatus = .processing

        // Define the output URL for the extracted audio
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outputURL = documentDirectory.appendingPathComponent("extractedAudio.wav")

        // Perform the audio extraction
        AudioExtractor.extractAudioAsWAV(from: videoURL, outputURL: outputURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self.audioProcessingStatus = .success(url.lastPathComponent)
                case .failure(let error):
                    self.audioProcessingStatus = .failure(error.localizedDescription)
                }
            }
        }
    }
    
    private func extractResizeAndPrepareFrames(from videoURL: URL) {
        let videoPreprocessor = VideoPreprocessor() // Assuming this is correctly initialized
        
        // Assuming extractAndResizeFrames function is implemented to extract and resize frames
        // and it returns an array of UIImage of frames resized to 96x96
        extractAndResizeFrames(from: videoURL, targetSize: CGSize(width: 96, height: 96)) { resizedFrames in
            do {
                // Now, use the resized frames to prepare the MLMultiArray
                let multiArray = try videoPreprocessor.framesToMultiArray(frames: resizedFrames)
                DispatchQueue.main.async {
                    self.videoProcessingStatus = .success("Video processed successfully with MLMultiArray.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.videoProcessingStatus = .failure("Failed to process video frames into MLMultiArray: \(error.localizedDescription)")
                }
            }
        }
    }



    private func preprocessVideo(from videoURL: URL) {
        let videoPreprocessor = VideoPreprocessor() // Instance of VideoPreprocessor
        videoProcessingStatus = .processing
        
        // Generate a unique filename for the converted video
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let dateString = dateFormatter.string(from: Date())
        let uniqueFilename = "convertedVideo_\(dateString).mp4"
        let outputURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(uniqueFilename)
        
        VideoPreprocessor.convertMOVToMP4(sourceURL: videoURL, outputURL: outputURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let convertedURL):
                    // Now call processVideoFrames from videoPreprocessor instance
                    videoPreprocessor.processVideoFrames(from: convertedURL) { result in
                        switch result {
                        case .success(let multiArray):
                            self.videoProcessingStatus = .success("Video processed successfully with MLMultiArray.")
                        case .failure(let error):
                            self.videoProcessingStatus = .failure("Failed to process video frames: \(error.localizedDescription)")
                        }
                    }
                case .failure(let error):
                    self.videoProcessingStatus = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func processVideoFrames(from videoURL: URL) {
        let videoPreprocessor = VideoPreprocessor() // Create an instance of VideoPreprocessor
        videoProcessingStatus = .processing

        // Correctly calling the instance method
        videoPreprocessor.processVideoFrames(from: videoURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let multiArray):
                    // Handle the success case, perhaps passing the MLMultiArray to your model for inference
                    self.videoProcessingStatus = .success("Video processed successfully.")
                case .failure(let error):
                    self.videoProcessingStatus = .failure("Failed to process video frames: \(error.localizedDescription)")
                }
            }
        }
    }


    
    
    private func preprocessAudioData(from audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        // Load the audio file
        guard let file = try? AVAudioFile(forReading: audioURL) else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "AudioPreprocessingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to load audio file."])))
            }
            return
        }

        let audioFormat = file.processingFormat
        let audioFrameCount = UInt32(file.length)
        var audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: audioFrameCount)!
        
        do {
            try file.read(into: audioBuffer)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }
        
        // Convert audio buffer to a format suitable for spectrogram generation
        // Placeholder for audio to spectrogram conversion
        // You would typically use FFT (Fast Fourier Transform) here, possibly via Accelerate framework

        // Once you have the spectrogram data, reshape it to fit the (1, 1, 1, 80, 16) shape
        // This might involve selecting specific frequencies and time steps, and normalizing the data
        
        DispatchQueue.main.async {
            completion(.success("Audio data processed successfully"))
        }
    }
}
    
    

    
    
private func preprocessVideoFrames(from videoURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
      let asset = AVAsset(url: videoURL)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true

      // Calculate the duration and frame extraction interval
      let duration = CMTimeGetSeconds(asset.duration)
      let frameInterval = duration / 6 // Adjust based on the number of frames you need

      var frames: [CGImage] = []
      for second in stride(from: 0, to: duration, by: frameInterval) {
          let cmTime = CMTimeMakeWithSeconds(Float64(second), preferredTimescale: 600)
          do {
              let image = try generator.copyCGImage(at: cmTime, actualTime: nil)
              frames.append(image)
              // Resize image to 96x96 and convert to your desired format (e.g., pixel buffer)
          } catch {
              DispatchQueue.main.async {
                  completion(.failure(error))
                  return
              }
          }
      }

      // Assuming you have a method to resize images and convert them to a format suitable for your model
      let resizedFrames = frames.map { resizeImageTo96x96($0) }
      
      // Convert the frames into the multi-array format required by your model
      // This step would involve creating a MLMultiArray and filling it with the pixel data from your frames
      // The actual implementation depends on how your model expects the input
      
      DispatchQueue.main.async {
          completion(.success("Video frames processed successfully"))
      }
  }
  
func resizeImageTo96x96(_ cgImage: CGImage) -> CGImage? {
    let size = CGSize(width: 96, height: 96)
    let renderer = UIGraphicsImageRenderer(size: size)
    let resizedImage = renderer.image { context in
        UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
    }
    return resizedImage.cgImage
}


    
    
    

    
    
    
    
    
    
    
    


extension ContentView.ProcessingStatus {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
