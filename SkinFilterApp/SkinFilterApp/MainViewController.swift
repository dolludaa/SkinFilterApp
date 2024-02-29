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

private struct Constants {
    static let cameraButtonCornerRadius = 15.0
    static let filterButtonCornerRadius = 15.0
    static let cameraOpenImageName = "cameraOpen"
    static let cameraCloseImageName = "cameraClose"
    static let filterImageName = "filterImage"
    static let videoQueueLabel = "videoQueue"
}

class ViewController: UIViewController {
    
    private let imageView = UIImageView()
    private let whiteView = UIView()
    private let cameraButton = UIButton()
    private let filterButton = UIButton()
    private let openCameraImage = UIImage(named: Constants.cameraOpenImageName)
    private let closeCameraImage = UIImage(named: Constants.cameraCloseImageName)
    private let filterImage = UIImage(named: Constants.filterImageName)
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let captureSession = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let filter = YUCIHighPassSkinSmoothing()
    private let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
    private var currentPixelBuffer: CVPixelBuffer?
    private lazy var faceDetectionRequest = makeFaceDetectionRequest()
    
    private var isCameraOpen = false
    private var isFilterApplied = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setUpStyle()
        setupCaptureSession()
    }
    
    private func setupLayout() {
        
        view.addSubview(imageView)
        view.addSubview(whiteView)
        view.addSubview(cameraButton)
        view.addSubview(filterButton)
        
        whiteView.translatesAutoresizingMaskIntoConstraints = false
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            whiteView.topAnchor.constraint(equalTo: view.topAnchor),
            whiteView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            whiteView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            whiteView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            cameraButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -12.5),
            cameraButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            
            filterButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 12.5),
            filterButton.bottomAnchor.constraint(equalTo: cameraButton.bottomAnchor)
            
        ])
    }
    
    private func setUpStyle() {
        whiteView.backgroundColor = .white
        
        imageView.frame = view.bounds
        imageView.contentMode = .scaleAspectFill
        
        cameraButton.layer.cornerRadius = Constants.cameraButtonCornerRadius
        cameraButton.setBackgroundImage(openCameraImage, for: .normal)
        cameraButton.addTarget(self, action: #selector(toggleCamera), for: .touchUpInside)
        
        filterButton.isHidden = true
        filterButton.setBackgroundImage(filterImage, for: .normal)
        filterButton.layer.cornerRadius = Constants.filterButtonCornerRadius
        filterButton.addTarget(self, action: #selector(toggleFilter), for: .touchUpInside)
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
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: Constants.videoQueueLabel))
        
        guard captureSession.canAddOutput(videoOutput) else {
            fatalError("Cannot add video output to the session")
        }
        
        captureSession.addOutput(videoOutput)
        captureSession.commitConfiguration()
    }
    
    private func closeCamera() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
    
    private func makeFaceDetectionRequest() -> VNDetectFaceRectanglesRequest {
        VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard error == nil,
                  let results = request.results as? [VNFaceObservation],
                  !results.isEmpty else { return }
            
            DispatchQueue.main.async {
                self?.processFaceDetection(results: results)
            }
        }
    }
    
    private func processFaceDetection(results: [VNFaceObservation]) {
        guard let currentPixelBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: currentPixelBuffer)
        
        if let processedImage = processFaces(for: results, in: ciImage),
           let outputCGImage = context.createCGImage(processedImage, from: processedImage.extent) {
            imageView.image = UIImage(cgImage: outputCGImage)
        }
    }
    
    private func processFaces(for observations: [VNFaceObservation], in ciImage: CIImage) -> CIImage? {
        guard let currentPixelBuffer else { return nil }
        var resultImage = ciImage
        
        for observation in observations {
            let faceBounds = VNImageRectForNormalizedRect(observation.boundingBox, Int(ciImage.extent.width), Int(ciImage.extent.height))
            
            filter.inputImage = CIImage(cvPixelBuffer: currentPixelBuffer)
            filter.inputAmount = 1.0
            filter.inputRadius = 7.0 * faceBounds.width / 750.0 as NSNumber
            
            guard let outputFaceImage = filter.outputImage else { continue }
            
            let width = faceBounds.width
            let height = faceBounds.height
            let ovalWidth = width * 1.2
            let ovalHeight = height * 1.4
            
            let centerY = faceBounds.midY + height * 0.1
            let centerX = faceBounds.midX
            let center = CIVector(x: centerX, y: centerY)
            
            guard let radialGradient = CIFilter(name: "CIRadialGradient", parameters: [
                "inputRadius0": min(ovalWidth, ovalHeight) / 2 as NSNumber,
                "inputRadius1": max(ovalWidth, ovalHeight) / 2 as NSNumber,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0),
                "inputCenter": center
            ])?.outputImage
            else { continue }
            
            let blendFilter = CIFilter(name: "CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: resultImage,
                kCIInputImageKey: outputFaceImage,
                kCIInputMaskImageKey: radialGradient
            ])
            
            if let blendedImage = blendFilter?.outputImage {
                resultImage = blendedImage.cropped(to: ciImage.extent)
            }
        }
        
        return resultImage
    }
    
    @objc private func toggleFilter() {
        isFilterApplied.toggle()
        
        filterButton.setBackgroundImage(UIImage(named: "filterImage"), for: .normal)
    }
    
    @objc private func toggleCamera() {
        if isCameraOpen {
            setCameraCloseState()
        } else {
            setCameraOpenState()
        }
    }
    
    private func setCameraOpenState() {
        createPreviewLayerIfNeeded()
        
        view.bringSubviewToFront(cameraButton)
        
        cameraButton.setBackgroundImage(closeCameraImage, for: .normal)
        
        isCameraOpen = true
        filterButton.isHidden = false
        whiteView.isHidden = true
    }
    
    private func createPreviewLayerIfNeeded() {
        guard previewLayer == nil else { return }
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        
        if let previewLayer {
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.insertSublayer(previewLayer, at: 0)
            previewLayer.connection?.videoOrientation = .portrait
        }
        
        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
            connection.videoOrientation = .portrait
        }
        
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }
    
    private func setCameraCloseState() {
        closeCamera()
        cameraButton.setBackgroundImage(openCameraImage, for: .normal)
        isCameraOpen = false
        filterButton.isHidden = true
        whiteView.isHidden = false
        imageView.image = nil
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        currentPixelBuffer = pixelBuffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        if isFilterApplied {
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                do {
                    try handler.perform([faceDetectionRequest])
                } catch {
                    print("Failed to perform face detection: \(error)")
                }
            }
        } else {
            
            DispatchQueue.main.async {
                self.imageView.image = UIImage(ciImage: ciImage)
            }
        }
    }
    
    func updateImage(_ ciImage: CIImage) {
        var finalImage: CIImage?
        
        if isFilterApplied {
            
            filter.inputImage = ciImage
            filter.inputAmount = 1.0
            filter.inputRadius = 10.0
            finalImage = filter.outputImage
        } else {
            finalImage = ciImage
        }
        
        if let finalImage = finalImage, let outputCGImage = context.createCGImage(finalImage, from: finalImage.extent) {
            DispatchQueue.main.async {
                self.imageView.image = UIImage(cgImage: outputCGImage)
            }
        }
    }
}
