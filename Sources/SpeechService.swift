import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechService: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var errorMessage: String?

    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

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

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch authStatus {
                case .authorized:
                    self.beginAudioSession()
                case .denied, .restricted:
                    self.errorMessage = "Разрешите доступ к микрофону и распознаванию речи в Настройках iOS."
                case .notDetermined:
                    self.errorMessage = "Требуется разрешение на запись звука."
                @unknown default:
                    self.errorMessage = "Не удалось получить доступ к микрофону."
                }
            }
        }
    }

    private func beginAudioSession() {
        recognitionTask?.cancel()
        recognitionTask = nil

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

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
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
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRecording = false

        let finalText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if !finalText.isEmpty {
            onComplete(finalText)
        }
    }
}
