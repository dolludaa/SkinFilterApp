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
    private var filterButton = UIButton()
    private var isFilterApplied = false

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
        // Ensure imageView is initialized before this point

        view.addSubview(imageView)
        imageView.frame = view.bounds // Or any other frame setup
        imageView.contentMode = .scaleAspectFill

        view.addSubview(whiteView)
        whiteView.backgroundColor = .white
        whiteView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            whiteView.topAnchor.constraint(equalTo: view.topAnchor),
            whiteView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            whiteView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            whiteView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        view.addSubview(cameraButton)
           cameraButton.translatesAutoresizingMaskIntoConstraints = false
           NSLayoutConstraint.activate([
               cameraButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -12.5), // Смещение влево от центра на половину расстояния между кнопками
               cameraButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
           ])
           
           view.addSubview(filterButton)
           filterButton.translatesAutoresizingMaskIntoConstraints = false
           filterButton.isHidden = true // Если кнопка должна быть видимой сразу
           NSLayoutConstraint.activate([
               filterButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 12.5), // Смещение вправо от центра на половину расстояния между кнопками
               filterButton.bottomAnchor.constraint(equalTo: cameraButton.bottomAnchor)
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
        
        filterButton.titleLabel?.font = .systemFont(ofSize: 16)
        filterButton.setBackgroundImage(UIImage(named: "filterImage"), for: .normal)
        filterButton.setTitleColor(.blue, for: .normal)
        filterButton.layer.cornerRadius = 15
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
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        guard captureSession.canAddOutput(videoOutput) else {
            fatalError("Cannot add video output to the session")
        }
        
        captureSession.addOutput(videoOutput)
        captureSession.commitConfiguration()
    }
    
    @objc private func toggleFilter() {
        isFilterApplied.toggle() // Переключаем состояние применения фильтра


      
      
            filterButton.setBackgroundImage(UIImage(named: "filterImage"), for: .normal)


        // Обновляем изображение с применением или без применения фильтра
        // Это условное выполнение требуется, если вы хотите немедленно обновить видимое изображение.
        // Вам может потребоваться вызвать обновление или перерисовку текущего изображения с фильтром или без него.
        guard let pixelBuffer = currentPixelBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        updateImage(ciImage)
    }

    
    @objc private func toggleCamera() {
        if isCameraOpen {
            closeCamera()
                   cameraButton.setBackgroundImage(openCameraImage, for: .normal)
                   isCameraOpen = false
            filterButton.isHidden = true
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
            filterButton.isHidden = false
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
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        if isFilterApplied {
            // Запускаем обнаружение лиц и фильтрацию в отдельном потоке, чтобы не блокировать основной поток
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                do {
                    try handler.perform([self.faceDetectionRequest])
                } catch {
                    print("Failed to perform face detection: \(error)")
                }
            }
        } else {
            // Обновляем изображение без применения фильтра
            DispatchQueue.main.async {
                self.imageView.image = UIImage(ciImage: ciImage)
            }
        }
    }


    func updateImage(_ ciImage: CIImage) {
        var finalImage: CIImage?

        if isFilterApplied {
            // Применяем фильтр
            // Это пример. Вам нужно адаптировать логику применения фильтра в соответствии с вашими потребностями.
            filter.inputImage = ciImage
            filter.inputAmount = 1.0 // Настройте в соответствии с вашим фильтром
            filter.inputRadius = 10.0 // Настройте в соответствии с вашим фильтром
            finalImage = filter.outputImage
        } else {
            // Не применяем фильтр
            finalImage = ciImage
        }

        if let finalImage = finalImage, let outputCGImage = context.createCGImage(finalImage, from: finalImage.extent) {
            DispatchQueue.main.async {
                self.imageView.image = UIImage(cgImage: outputCGImage)
            }
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
