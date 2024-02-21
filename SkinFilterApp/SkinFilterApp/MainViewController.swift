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

        
    private var cameraButton = UIButton()

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
        imageView.frame = view.frame
        imageView.contentMode = .scaleAspectFill
        
        cameraButton.titleLabel?.textColor = .blue
        cameraButton.setTitleColor(.blue, for: .normal)
        cameraButton.layer.cornerRadius = 15
        cameraButton.setTitle("Open Camera", for: .normal)
        cameraButton.addTarget(self, action: #selector(openCamera), for: .touchUpInside)

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
        view.bringSubviewToFront(imageView)
    }
    
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.leftMirrored)
        if let filteredCIImage = applySurfaceBlur(to: ciImage) {
            let outputCGImage = context.createCGImage(filteredCIImage, from: filteredCIImage.extent)
            DispatchQueue.main.async { [weak self] in
                self?.imageView.image = UIImage(cgImage: outputCGImage!)
            }
        }
    }
    
    func applySurfaceBlur(to ciImage: CIImage) -> CIImage? {
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
