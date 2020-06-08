import UIKit
import HaishinKit
import Photos
import VideoToolbox

final class PreferenceViewController: UIViewController {
    
    private static let maxRetryCount = 10
    
    @IBOutlet weak var streamToggle: UIButton!
    @IBOutlet private weak var urlField: UITextField?
    @IBOutlet private weak var streamNameField: UITextField?
    @IBOutlet weak var turnOnCamera: UISwitch!
    
    @IBOutlet weak var pageTitle: UILabel!
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        urlField?.text = Preference.defaultInstance.uri
        streamNameField?.text = Preference.defaultInstance.streamName
    }
    
    private var rtmpConnection = RTMPConnection()
    private var rtmpStream: RTMPStream!
    private var sharedObject: RTMPSharedObject!
    private var currentEffect: VideoEffect?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var retryCount: Int = 0
    private var videoBitrateValue = 0
    private var audioBitrateValue = 0
    private var rtmpUrl = "";
    private var rtmpSec = "";

    override func viewDidLoad() {
        super.viewDidLoad()

        rtmpStream = RTMPStream(connection: rtmpConnection)
        if let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) {
            rtmpStream.orientation = orientation
        }
        rtmpStream.captureSettings = [
            .sessionPreset: AVCaptureSession.Preset.hd1280x720,
            .continuousAutofocus: true,
            .continuousExposure: true
            // .preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode.auto
        ]
        rtmpStream.videoSettings = [
            .width: 720,
            .height: 1280
        ]
        rtmpStream.mixer.recorder.delegate = ExampleRecorderDelegate.shared

        videoBitrateValue = 32768  / 1024
        audioBitrateValue = 131072 / 1024

    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rtmpStream.attachAudio(AVCaptureDevice.default(for: .audio)) { error in
            logger.warn(error.description)
        }
        if turnOnCamera.isOn {
            rtmpStream.attachCamera(DeviceUtil.device(withPosition: currentPosition)) { error in
                logger.warn(error.description)
            }
        }
        else {
            rtmpStream.attachScreen(ScreenCaptureSession(shared: UIApplication.shared))
        }

         
        rtmpStream.addObserver(self, forKeyPath: "currentFPS", options: .new, context: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
         super.viewWillDisappear(animated)
       rtmpStream.removeObserver(self, forKeyPath: "currentFPS")
       rtmpStream.close()
       rtmpStream.dispose()
    }

    @IBAction func on(open: UIButton) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let controller: UIViewController = storyboard.instantiateViewController(withIdentifier: "PopUpLive")
        present(controller, animated: true, completion: nil)
    }
    @IBAction func StartStreaming(_ sender: Any) {
        pageTitle.text = urlField?.text
        rtmpUrl = urlField?.text ?? ""
        rtmpSec = streamNameField?.text ?? ""
        
        if streamToggle.isSelected {
            UIApplication.shared.isIdleTimerDisabled = false
            rtmpConnection.close()
            rtmpConnection.removeEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
            rtmpConnection.removeEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
            streamToggle.setTitle("Start", for: [])
        } else {
            UIApplication.shared.isIdleTimerDisabled = true
            rtmpConnection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
            rtmpConnection.addEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
            rtmpConnection.connect(rtmpUrl)
            streamToggle.setTitle("stop", for: [])
        }
        streamToggle.isSelected.toggle()
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if Thread.isMainThread {
            pageTitle.text = "\(rtmpStream.currentFPS)"
        }
    }
    
    
    @IBAction func on(publish: UIButton) {
        
    }
    
    
    @objc
    private func rtmpStatusHandler(_ notification: Notification) {
        let e = Event.from(notification)
        guard let data: ASObject = e.data as? ASObject, let code: String = data["code"] as? String else {
            return
        }
        logger.info(data)
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            retryCount = 0
            rtmpStream!.publish(rtmpSec)
            // sharedObject!.connect(rtmpConnection)
        case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectClosed.rawValue:
            guard retryCount <= PreferenceViewController.maxRetryCount else {
                return
            }
            Thread.sleep(forTimeInterval: pow(2.0, Double(retryCount)))
            rtmpConnection.connect(rtmpUrl)
            retryCount += 1
        default:
            break
        }
    }

    @objc
    private func rtmpErrorHandler(_ notification: Notification) {
        logger.error(notification)
        rtmpConnection.connect(rtmpUrl)
    }
}

extension PreferenceViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if urlField == textField {
            Preference.defaultInstance.uri = textField.text
        }
        if streamNameField == textField {
            Preference.defaultInstance.streamName = textField.text
        }
        textField.resignFirstResponder()
        return true
    }
}
