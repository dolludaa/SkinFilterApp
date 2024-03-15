//
//  MainViewController.swift
//  SkinFilterApp
//
//  Created by Людмила Долонтаева on 2024-02-13.
//

import AVFoundation
import UIKit
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
    
    private let captureSession = AVCaptureSession()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var faceLayers: [CAShapeLayer] = []
    
    private let imageView = UIImageView()
    private let whiteView = UIView()
    private let cameraButton = UIButton()
    private let filterButton = UIButton()
    private let openCameraImage = UIImage(named: Constants.cameraOpenImageName)
    private let closeCameraImage = UIImage(named: Constants.cameraCloseImageName)
    private let filterImage = UIImage(named: Constants.filterImageName)
    private var faceObservations: [VNFaceObservation] = []

    private var isCameraOpen = false
    private var isFilterApplied = false
    
    override func viewDidLoad() {
            super.viewDidLoad()
            setupLayout()
            setUpStyle()
            setupCaptureSession()
        }

    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.view.frame
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
    
        videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: Constants.videoQueueLabel))
    
            guard captureSession.canAddOutput(videoDataOutput) else {
                fatalError("Cannot add video output to the session")
            }
    
            captureSession.addOutput(videoDataOutput)
            captureSession.commitConfiguration()
        }
    
    private func setCameraOpenState() {
        createPreviewLayerIfNeeded()

        view.bringSubviewToFront(cameraButton)

        cameraButton.setBackgroundImage(closeCameraImage, for: .normal)

        isCameraOpen = true
        filterButton.isHidden = false
        whiteView.isHidden = true
    }
    
    private func setCameraCloseState() {
        stopCamera()
        cameraButton.setBackgroundImage(openCameraImage, for: .normal)
        isCameraOpen = false
        filterButton.isHidden = true
        whiteView.isHidden = false
        imageView.image = nil
    }
    
    private func stopCamera() {
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.stopRunning()
            }
        }
    }
    
    private func createPreviewLayerIfNeeded() {
        if previewLayer.superlayer == nil {
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.insertSublayer(previewLayer, at: 0)
        }

        previewLayer.connection?.videoOrientation = .portrait

        if let connection = videoDataOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
            connection.videoOrientation = .portrait
        }

        startCamera()
    }
    
    private func applyMaskToImageView() {
        let maskLayer = combineMasks(masks: faceLayers)
        guard let maskImage = layerToImage(layer: maskLayer) else {
            return
        }

        let maskLayerForImage = CALayer()
        maskLayerForImage.contents = maskImage
        maskLayerForImage.frame = imageView.bounds
        imageView.layer.mask = maskLayerForImage
    }

    private func layerToImage(layer: CAShapeLayer) -> CGImage? {
        let size = imageView.bounds.size
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        layer.bounds = imageView.bounds
        layer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        layer.render(in: context)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image?.cgImage
    }

    private func startCamera() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
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
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let faceDetectionRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request: VNRequest, error: Error?) in
            DispatchQueue.main.async {
                self.faceLayers.forEach({ drawing in drawing.removeFromSuperlayer() })
                
                if let observations = request.results as? [VNFaceObservation] {
                    self.handleFaceDetectionObservations(observations: observations)
                }
            }
        })
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .leftMirrored, options: [:])
        
        do {
            try imageRequestHandler.perform([faceDetectionRequest])
        } catch {
            print(error.localizedDescription)
        }
    }
    
    private func handleFaceDetectionObservations(observations: [VNFaceObservation]) {
        faceLayers = []
        for observation in observations {
            let faceRectConverted = self.previewLayer.layerRectConverted(fromMetadataOutputRect: observation.boundingBox)
            let faceRectanglePath = CGPath(rect: faceRectConverted, transform: nil)
            
            let faceLayer = CAShapeLayer()
            faceLayer.path = faceRectanglePath
            faceLayer.fillColor = UIColor.clear.cgColor
            faceLayer.strokeColor = UIColor.yellow.cgColor
            
            self.faceLayers.append(faceLayer)
            //            self.view.layer.addSublayer(faceLayer)
            
            //FACE LANDMARKS
            if let landmarks = observation.landmarks {
                if let leftEye = landmarks.leftEye {
                    self.handleLandmark(leftEye, faceBoundingBox: faceRectConverted)
                }
                
                if let rightEye = landmarks.rightEye {
                    self.handleLandmark(rightEye, faceBoundingBox: faceRectConverted)
                }
                
                if let outerLips = landmarks.outerLips {
                    self.handleLandmark(outerLips, faceBoundingBox: faceRectConverted)
                }
                if let innerLips = landmarks.innerLips {
                    self.handleLandmark(innerLips, faceBoundingBox: faceRectConverted)
                }
                if let outerLips = landmarks.outerLips {
                    self.handleLandmark(outerLips, faceBoundingBox: faceRectConverted)
                }
            }
            
            
        }
        
        view.layer.mask = nil

                imageView.layer.mask = combineMasks(masks: faceLayers)
    }
    
    private func handleLandmark(_ eye: VNFaceLandmarkRegion2D, faceBoundingBox: CGRect) {
        let landmarkPath = CGMutablePath()
        let landmarkPathPoints = eye.normalizedPoints
            .map({ eyePoint in
                CGPoint(
                    x: eyePoint.y * faceBoundingBox.height + faceBoundingBox.origin.x,
                    y: eyePoint.x * faceBoundingBox.width + faceBoundingBox.origin.y)
            })
        landmarkPath.addLines(between: landmarkPathPoints)
        landmarkPath.closeSubpath()
        let landmarkLayer = CAShapeLayer()
        landmarkLayer.path = landmarkPath
        landmarkLayer.fillColor = UIColor.green.cgColor
        landmarkLayer.strokeColor = UIColor.green.cgColor
        
        self.faceLayers.append(landmarkLayer)
        //        self.view.layer.addSublayer(landmarkLayer)
    }
}

func combineMasks(masks: [CAShapeLayer]) -> CAShapeLayer {
    let combinedPath = CGMutablePath()
    
    for mask in masks {
        if let path = mask.path {
            combinedPath.addPath(path)
        }
    }
    
    let combinedMaskLayer = CAShapeLayer()
    combinedMaskLayer.path = combinedPath
    combinedMaskLayer.fillRule = .evenOdd
    
    return combinedMaskLayer
}

