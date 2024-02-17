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

class ViewController: UIViewController {

        
    lazy var cameraButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Open Camera", for: .normal)
        button.addTarget(self, action: #selector(openCamera), for: .touchUpInside)
        return button
    }()

    var previewLayer: AVCaptureVideoPreviewLayer!
    let captureSession = AVCaptureSession()
    var videoOutput = AVCaptureVideoDataOutput()
    var videoDeviceInput: AVCaptureDeviceInput!
    
    private let imageView = UIImageView()
    private let filter = YUCIHighPassSkinSmoothing()
    private let context = CIContext(options: [CIContextOption.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupCaptureSession()
    }

    private func setupLayout() {
           view.addSubview(cameraButton)
           cameraButton.translatesAutoresizingMaskIntoConstraints = false
           NSLayoutConstraint.activate([
               cameraButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
               cameraButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
           ])
           
           view.addSubview(imageView)
        imageView.frame = view.frame
        imageView.contentMode = .scaleAspectFill
       }

    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice!)
            if captureSession.canAddInput(videoDeviceInput) {
                captureSession.addInput(videoDeviceInput)
            } else {
                fatalError("Cannot add video device input to the session")
            }
        } catch {
            fatalError(error.localizedDescription)
        }
        
        videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            fatalError("Cannot add video output to the session")
        }
        
        captureSession.commitConfiguration()
    }
    
    @objc private func openCamera() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }

//        view.bringSubviewToFront(cameraButton)
        view.bringSubviewToFront(imageView)
    }

}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if let filteredCIImage = applySurfaceBlur(to: ciImage) {
//            DispatchQueue.main.async {
//                self.updatePreviewLayer(with: filteredCIImage)
//            }
        }
    }

    func applySurfaceBlur(to ciImage: CIImage) -> CIImage? {
        processImage(to: ciImage)
        let filter = YUCIHighPassSkinSmoothing()
        filter.inputImage = ciImage
        filter.inputAmount = 0.9
        filter.inputRadius = 7.0 * ciImage.extent.width / 750.0 as NSNumber
        
        return filter.outputImage
    }
    
    func processImage(to ciImage: CIImage) {
        filter.inputImage = ciImage
        filter.inputAmount = 0.9
        filter.inputRadius = 7.0 * ciImage.extent.width/750.0 as NSNumber
        let outputCIImage = filter.outputImage!
        
        let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent)
        
        DispatchQueue.main.async { [self] in
            let outputUIImage = UIImage(
                cgImage: outputCGImage!,
                scale: imageView.image?.scale ?? 1,
                orientation: imageView.image?.imageOrientation ?? .leftMirrored
            )
            
            imageView.image = outputUIImage
        }
        
    }

    func updatePreviewLayer(with ciImage: CIImage) {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .left)
        DispatchQueue.main.async {
            self.imageView.image = uiImage
        }
    }

}
