//
//  MainViewController.swift
//  SkinFilterApp
//
//  Created by Людмила Долонтаева on 2024-02-13.
//

import UIKit
import AVFoundation
import MetalPetal
import YUCIHighPassSkinSmoothing
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var cameraButton = UIButton()
    var previewLayer: AVCaptureVideoPreviewLayer!
    let captureSession = AVCaptureSession()
    var videoOutput = AVCaptureVideoDataOutput()
    var videoDeviceInput: AVCaptureDeviceInput!
    
    private let imageView = UIImageView()
    private let filter = YUCIHighPassSkinSmoothing()
    private let context = CIContext(options: [CIContextOption.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
    var currentPixelBuffer: CVPixelBuffer?
    
    lazy var faceDetectionRequest: VNDetectFaceRectanglesRequest = {
        VNDetectFaceRectanglesRequest(completionHandler: { [weak self] request, error in
            guard let self = self, error == nil, let results = request.results as? [VNFaceObservation], !results.isEmpty else { return }
            DispatchQueue.main.async {
                guard let pixelBuffer = self.currentPixelBuffer else { return }
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                if let processedImage = self.processFaces(for: results, in: ciImage),
                   let outputCGImage = self.context.createCGImage(processedImage, from: processedImage.extent) {
                    self.imageView.image = UIImage(cgImage: outputCGImage)
                }
            }
        })
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setUpStyle()
        setupCaptureSession()
    }
    
    private func setupLayout() {
        view.addSubview(cameraButton)
        view.addSubview(imageView)
        
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            cameraButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cameraButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setUpStyle() {
        imageView.frame = view.bounds
        imageView.contentMode = .scaleAspectFill
        
        cameraButton.titleLabel?.font = .systemFont(ofSize: 16)
        cameraButton.setTitleColor(.blue, for: .normal)
        cameraButton.layer.cornerRadius = 15
        cameraButton.setTitle("Open Camera", for: .normal)
        cameraButton.addTarget(self, action: #selector(openCamera), for: .touchUpInside)
    }
    
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoDeviceInput) else {
            fatalError("Cannot add video device input to the session")
        }
        
        captureSession.addInput(videoDeviceInput)
        
        videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        guard captureSession.canAddOutput(videoOutput) else {
            fatalError("Cannot add video output to the session")
        }
        
        captureSession.addOutput(videoOutput)
        captureSession.commitConfiguration()
    }
    
    @objc private func openCamera() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)
        previewLayer.connection?.videoOrientation = .portrait
        
        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
            connection.videoOrientation = .portrait
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }


    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        currentPixelBuffer = pixelBuffer
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([faceDetectionRequest])
        } catch {
            print("Failed to perform face detection: \(error)")
        }
    }
    
    func processFaces(for observations: [VNFaceObservation], in ciImage: CIImage) -> CIImage? {
        var resultImage = ciImage
        
        for observation in observations {
            let faceBounds = VNImageRectForNormalizedRect(observation.boundingBox, Int(ciImage.extent.width), Int(ciImage.extent.height))
            let faceCIImage = ciImage.cropped(to: faceBounds)
            
            filter.inputImage = faceCIImage
            filter.inputAmount = 0.9
            filter.inputRadius = 7.0 * faceCIImage.extent.width / 750.0 as NSNumber
            
            guard let outputFaceImage = filter.outputImage else { continue }
            
            // Создаем овальную маску
            let center = CIVector(x: faceBounds.midX, y: faceBounds.midY)
            let radius = max(faceBounds.width, faceBounds.height) / 2
            let radialGradient = CIFilter(name: "CIRadialGradient", parameters: [
                "inputRadius0": radius * 0.9 as NSNumber,
                "inputRadius1": radius as NSNumber,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0),
                "inputCenter": center
            ])!.outputImage!.cropped(to: faceBounds)
            
            if let blendFilter = CIFilter(name: "CIBlendWithMask",
                                           parameters: [kCIInputBackgroundImageKey: resultImage,
                                                        kCIInputImageKey: outputFaceImage,
                                                        kCIInputMaskImageKey: radialGradient]) {
                resultImage = blendFilter.outputImage!
            }
        }
        
        return resultImage
    }


}
