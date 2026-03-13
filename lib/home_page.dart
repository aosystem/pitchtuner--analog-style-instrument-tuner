import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pitchtuner/parse_locale_tag.dart';
import 'package:pitchtuner/setting_page.dart';
import 'package:pitchtuner/theme_color.dart';
import 'package:pitchtuner/theme_mode_number.dart';
import 'package:pitchtuner/ad_manager.dart';
import 'package:pitchtuner/loading_screen.dart';
import 'package:pitchtuner/model.dart';
import 'package:pitchtuner/main.dart';
import 'package:pitchtuner/ad_banner_widget.dart';
import 'package:pitchtuner/l10n/app_localizations.dart';


class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});
  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  late AdManager _adManager;
  late ThemeColor _themeColor;
  bool _isReady = false;
  bool _isFirst = true;
  //
  final _audioRecorder = AudioRecorder();
  late PitchDetector _pitchDetector;
  StreamSubscription<Uint8List>? _audioRecorderSubscription;
  final int _sampleRate = 44100;
  final int _bufferSize = 2048;
  double _frequency = 0.0;
  String _note = "-";
  double _cents = 0.0;
  //
  String _message = '';

  @override
  void initState() {
    super.initState();
    _initState();
  }

  void _initState() async {
    _pitchDetector = PitchDetector(
      audioSampleRate: _sampleRate.toDouble(),
      bufferSize: _bufferSize,
    );
    _adManager = AdManager();
    if (mounted) {
      setState(() {
        _isReady = true;
      });
    }
  }

  @override
  void dispose() {
    _audioRecorderSubscription?.cancel();
    _audioRecorder.stop();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startTuning() async {
    setState(() {
      _message = '';
    });
    await _audioRecorderSubscription?.cancel();
    _audioRecorderSubscription = null;
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (await _audioRecorder.hasPermission()) {
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      );
      final stream = await _audioRecorder.startStream(config);
      if (!mounted) {
        return;
      }
      _audioRecorderSubscription = stream.listen((Uint8List data) async {
        if (!mounted) {
          return;
        }
        try {
          final alignedData = Uint8List.fromList(data);
          final int16Data = alignedData.buffer.asInt16List();
          final doubleSamples = int16Data.map((v) => v / 32768.0).toList();
          if (doubleSamples.length < 512) {
            return;
          }
          final result = await _pitchDetector.getPitchFromFloatBuffer(doubleSamples);
          if (!mounted) {
            return;
          }
          if (result.pitched && result.probability > 0.8) {
            _updateTuningData(result.pitch);
          }
        } catch (e) {
        }
      });
    } else {
      setState(() {
        _message = AppLocalizations.of(context)!.microphonePermission;
      });
    }
  }

  void _updateTuningData(double pitch) {
    double log2Value = math.log(pitch / 440.0) / math.log(2.0);
    double midiDouble = (12.0 * log2Value) + 69.0;
    int m = midiDouble.round();
    double idealFreq = 440.0 * math.pow(2.0, (m - 69.0) / 12.0);
    double diffCents = 1200 * (math.log(pitch / idealFreq) / math.log(2.0));
    final notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    String noteName = (m >= 0) ? notes[m % 12] : "-";
    int octave = (m ~/ 12) - 1;
    setState(() {
      _frequency = pitch;
      _note = "$noteName$octave";
      _cents = diffCents.clamp(-50.0, 50.0);
    });
  }

  String _formatCents(double value) {
    final sign = value >= 0 ? '+' : '-';
    final absValue = value.abs();
    String intPart = absValue.floor().toString().padLeft(2, '0');
    if (intPart[0] == '0') {
      intPart = ' ${intPart[1]}';
    }
    final decimalPart = ((absValue * 10) % 10).floor();
    return "$sign$intPart.$decimalPart";
  }

  void _onSetting() async {
    final updatedSettings = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingPage(),
      ),
    );
    if (updatedSettings != null) {
      if (mounted) {
        final mainState = context.findAncestorStateOfType<MainAppState>();
        if (mainState != null) {
          mainState
            ..locale = parseLocaleTag(Model.languageCode)
            ..themeMode = ThemeModeNumber.numberToThemeMode(Model.themeNumber)
            ..setState(() {});
        }
      }
      if (mounted) {
        setState(() {
          _isFirst = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady == false) {
      return const LoadingScreen();
    }
    if (_isFirst) {
      _isFirst = false;
      _startTuning();
      _themeColor = ThemeColor(context: context);
    }
    final bool isInTune = _cents.abs() < 5 && _note != "-";
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _themeColor.mainBackColor,
        elevation: 0,
        actions: [
          IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.settings,
              color: _themeColor.mainForeColor.withValues(alpha: 0.5),
            ),
            onPressed: _onSetting,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _themeColor.mainBackColor,
              _themeColor.mainBackColor2,
            ],
          ),
        ),
        child: SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(_note,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.orbitron(
                      color: isInTune ? _themeColor.mainAccentForeColor : Colors.white,
                      fontSize: 80,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(120),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset('assets/image/body.png'),
                            ]
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Transform.rotate(
                                angle: _cents * 3.1415926535 / 180 * 1.2,
                                child: Image.asset('assets/image/needle.png'),
                              )
                            ]
                          ),
                          Align(
                            alignment: Alignment(0, 0.47),
                            child: Text(_formatCents(_cents),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.shareTechMono(
                                color: isInTune ? _themeColor.mainAccentForeColor : Colors.orangeAccent,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ]
                      )
                    )
                  )
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: _frequency.toStringAsFixed(2),
                          style: GoogleFonts.shareTechMono(
                            color: _themeColor.mainAccentForeColor,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        WidgetSpan(child: SizedBox(width: 4)),
                        TextSpan(
                          text: "Hz",
                          style: GoogleFonts.shareTechMono(
                            color: _themeColor.mainAccentForeColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: Text(_message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: 100),
              ],
            )
          )
        )
      ),
      bottomNavigationBar: Container(
        color: _themeColor.mainBackColor2,
        child: AdBannerWidget(adManager: _adManager),
      ),
    );
  }
}
