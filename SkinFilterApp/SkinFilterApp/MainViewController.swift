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
        imageView.translatesAutoresizingMaskIntoConstraints = false
//        imageView.transform = imageView.transform.rotated(by: .pi / 2)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
            imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5)
        ])
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


//#Preview {
//    MainViewController()
//}

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
        
        // Предполагаем, что `applySurfaceBlur` возвращает CIImage.
        // В реальном примере, вы бы использовали MetalPetal для применения фильтра.
        if let filteredCIImage = applySurfaceBlur(to: ciImage) {
            DispatchQueue.main.async {
                self.updatePreviewLayer(with: filteredCIImage)
            }
        }
    }

    func applySurfaceBlur(to ciImage: CIImage) -> CIImage? {
        let filter = YUCIHighPassSkinSmoothing()
        filter.inputRadius = 80
        filter.inputImage = ciImage
        filter.inputAmount = 0
        filter.inputSharpnessFactor = 0
        return filter.outputImage
    }

    func updatePreviewLayer(with ciImage: CIImage) {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Определяем ориентацию изображения. Это значение должно соответствовать фактической ориентации исходного изображения.
        // Вы можете получить это значение из AVCaptureConnection или другого источника, в зависимости от того, как вы получаете изображение.
        // Здесь используется .right в качестве примера.
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        DispatchQueue.main.async {
            self.imageView.image = uiImage
        }
    }

}
