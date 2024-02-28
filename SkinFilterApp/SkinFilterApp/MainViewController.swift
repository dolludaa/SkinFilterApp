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
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let captureSession = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var videoDeviceInput: AVCaptureDeviceInput!
    private var isCameraOpen = false
    
    private var openCameraImage: UIImage?
    private var closeCameraImage: UIImage?
    
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
    
    private let whiteView = UIView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setUpStyle()
        setupCaptureSession()
    }
    
    private func setupLayout() {
        view.addSubview(imageView)
        view.addSubview(whiteView)
        whiteView.backgroundColor = .white
        
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraButton)
        
        NSLayoutConstraint.activate([
            cameraButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cameraButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        
        whiteView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            whiteView.topAnchor.constraint(equalTo: view.topAnchor),
            whiteView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            whiteView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            whiteView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setUpStyle() {
        imageView.frame = view.bounds
        imageView.contentMode = .scaleAspectFill
        
        openCameraImage = UIImage(named: "cameraOpen")
        closeCameraImage = UIImage(named: "cameraClose")

        
        cameraButton.titleLabel?.font = .systemFont(ofSize: 16)
        cameraButton.setTitleColor(.blue, for: .normal)
        cameraButton.layer.cornerRadius = 15
        cameraButton.setBackgroundImage(openCameraImage, for: .normal)
        cameraButton.addTarget(self, action: #selector(toggleCamera), for: .touchUpInside)
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
    
    @objc private func toggleCamera() {
        if isCameraOpen {
            closeCamera()
                   cameraButton.setBackgroundImage(openCameraImage, for: .normal)
                   isCameraOpen = false
            
            whiteView.isHidden = false
        } else {
            if previewLayer == nil {
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
                
                if !captureSession.isRunning {
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        self?.captureSession.startRunning()
                    }
                }
            }
            
            view.bringSubviewToFront(cameraButton)
        
            cameraButton.setBackgroundImage(closeCameraImage, for: .normal)

            isCameraOpen = true
        
            whiteView.isHidden = true
        }
    }

    private func closeCamera() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
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
            
            filter.inputImage = CIImage(cvPixelBuffer: currentPixelBuffer!)
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
            
            let radialGradient = CIFilter(name: "CIRadialGradient", parameters: [
                "inputRadius0": min(ovalWidth, ovalHeight) / 2 as NSNumber,
                "inputRadius1": max(ovalWidth, ovalHeight) / 2 as NSNumber,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0),
                "inputCenter": center
            ])!.outputImage!
            
            let blendFilter = CIFilter(name: "CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: resultImage,
                kCIInputImageKey: outputFaceImage,
                kCIInputMaskImageKey: radialGradient
            ])!
            
            if let blendedImage = blendFilter.outputImage {
                resultImage = blendedImage.cropped(to: ciImage.extent)
            }
        }
        
        return resultImage
    }
}
