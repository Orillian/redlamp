#if !REDLAMP_APP_STORE
    import Foundation

    public extension FirmwareFilmModel.Files {
        /// A model whose stages are identities, for every simulation at every setting the Camera
        /// Recipe controls offer, so tests and the regression suite run on a Mac without the model
        /// folder. None of its numbers come from the folder.
        static func identity() throws -> FirmwareFilmModel.Files {
            let simulations = FirmwareSimulation.allCases
            func stage(_ simulation: FirmwareSimulation) -> [String: Any] {
                [
                    "matrix": [1, 0, 0, 0, 1, 0, 0, 0, 1], "hdr": [0], "curves": [[0, 1], [0, 1], [0, 1]],
                    "chroma": [[1, 0], [0, 1]], "monochrome": simulation.isMonochrome,
                ]
            }
            // Half steps of Highlight and Shadow Tone, from the lowest at key 0.
            let stepsPerUnit = 2
            let toneRange = FirmwareLookSettings.toneRange
            let neutral = Int(-toneRange.lowerBound * Double(stepsPerUnit))
            let highest = Int((toneRange.upperBound - toneRange.lowerBound) * Double(stepsPerUnit))
            let tones = Dictionary(uniqueKeysWithValues: (0 ... highest).map { (String($0), [1, 1]) })
            let ranges = FirmwareLookSettings.dynamicRanges
            let gains = Dictionary(uniqueKeysWithValues: ranges.indices.map { (String($0), ["H": tones, "S": tones]) })
            let constants: [String: Any] = [
                "bins_per_stop": 1, "exposure_k": 1, "gain_unit": 1, "gain_clip_bin": 0,
                "tone_key_neutral": neutral, "tone_key_steps_per_unit": stepsPerUnit,
                "dr_index": Dictionary(uniqueKeysWithValues: ranges.enumerated().map { (String($1), $0) }),
                "luma_weights": [0.25, 0.5, 0.25], "luma_floor": 0.5, "matrix_unit": 1, "knot_intervals_per_header": 1,
                "curve_input_max": 1, "curve_output_max": 1, "ycbcr_matrix": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
                "chroma_unit": 1,
                "color_factor": Dictionary(uniqueKeysWithValues: FirmwareLookSettings.colorRange
                    .map { (String($0), 1) }),
                "color_factor_unit": 1, "toning_per_step": ["wc": [0, 0], "mg": [0, 0]], "toning_unit": 1,
                "toning_taper_luma_scale": 1, "toning_taper_y": [0, 1], "toning_taper_w": [1, 1], "sepia_unit": 1,
            ]
            let calibration: [String: Any] = [
                "pre_matrix": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "chroma_scale": [1, 1], "chroma_swap": false,
                "gamut": false,
            ]
            func json(_ object: Any) throws -> Data {
                try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            }
            return try FirmwareFilmModel.Files(
                parameters: json(Dictionary(uniqueKeysWithValues: simulations.map { ($0.modelName, stage($0)) })),
                toneGains: json(Dictionary(uniqueKeysWithValues: simulations.map { ($0.modelName, gains) })),
                calibration: json(calibration),
                constants: json(constants),
            )
        }

        /// The four files written into `folder`, as a model folder holds them.
        func write(to folder: URL) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, data) in zip(FirmwareFilmModel.fileNames, [parameters, toneGains, calibration, constants]) {
                try data.write(to: folder.appending(path: name))
            }
        }
    }
#endif
