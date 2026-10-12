import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechService: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var errorMessage: String?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var hasTapInstalled = false

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")) ?? SFSpeechRecognizer()
        setupInterruptionObserver()
    }

    private func setupInterruptionObserver() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            self.stopRecording { _ in }
        }
    }

    func toggleRecording(onComplete: @escaping (String) -> Void) {
        if isRecording {
            stopRecording(onComplete: onComplete)
        } else {
            startRecording()
        }
    }

    func startRecording() {
        recognizedText = ""
        errorMessage = nil

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Распознавание речи временно недоступно на устройстве."
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch authStatus {
                case .authorized:
                    self.beginAudioSession()
                case .denied, .restricted:
                    self.errorMessage = "Разрешите доступ к микрофону и распознаванию речи в Настройках iOS."
                case .notDetermined:
                    self.errorMessage = "Требуется подтвердить разрешение на запись звука."
                @unknown default:
                    self.errorMessage = "Не удалось получить доступ к микрофону."
                }
            }
        }
    }

    private func beginAudioSession() {
        cleanupCurrentTask()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Ошибка аудиосессии: \(error.localizedDescription)"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = [
            "Mobile Gestalt", "MobileGestalt", "Gestalt",
            "iOS", "SwiftUI", "API", "OpenRouter", "GitHub", "Nemotron"
        ]

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 else {
            errorMessage = "Аудиовход недоступен или не настроен на устройстве."
            return
        }

        safeRemoveTap()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        hasTapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            safeRemoveTap()
            errorMessage = "Не удалось запустить микрофон: \(error.localizedDescription)"
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
        }
    }

    func stopRecording(onComplete: @escaping (String) -> Void) {
        guard isRecording else { return }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        safeRemoveTap()
        recognitionRequest?.endAudio()
        isRecording = false

        let finalText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupCurrentTask()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if !finalText.isEmpty {
            onComplete(finalText)
        }
    }

    private func safeRemoveTap() {
        if hasTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
    }

    private func cleanupCurrentTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
