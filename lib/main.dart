import 'dart:io';
import 'dart:typed_data'; 
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Automated PDF Modifier',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PdfModifierScreen(),
    );
  }
}

class PdfModifierScreen extends StatefulWidget {
  const PdfModifierScreen({super.key});

  @override
  State<PdfModifierScreen> createState() => _PdfModifierScreenState();
}

class _PdfModifierScreenState extends State<PdfModifierScreen> {
  bool _isProcessing = false;
  String _statusMessage = "Upload a PDF to instantly rewrite text layouts dynamically.";

  Future<void> _processAndDownloadPdf() async {
    try {
      // 1. Pick File
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, 
      );

      if (result == null || result.files.isEmpty) return; 

      // Capture the original file name dynamically
      String originalFileName = result.files.first.name;
      if (!originalFileName.toLowerCase().endsWith('.pdf')) {
        originalFileName = '$originalFileName.pdf';
      }

      setState(() {
        _isProcessing = true;
        _statusMessage = "Processing transaction queue and updating summary metrics...";
      });

      // 2. Read bytes based on platform route
      Uint8List? fileBytes;
      if (kIsWeb) {
        fileBytes = result.files.first.bytes;
      } else {
        final filePath = result.files.first.path;
        if (filePath != null) {
          fileBytes = await File(filePath).readAsBytes();
        }
      }

      if (fileBytes == null) throw Exception("Failed to parse document data bytes.");

      // 3. Mount Extraction Layout Engines with Password Safeguards
      PdfDocument document;
      try {
        document = PdfDocument(inputBytes: fileBytes);
      } catch (e) {
        if (e.toString().contains('password') || e.toString().contains('Encrypted') || e.toString().contains('encrypted')) {
          document = PdfDocument(inputBytes: fileBytes, password: '348644008');
        } else {
          rethrow;
        }
      }

      final PdfTextExtractor extractor = PdfTextExtractor(document);
      PdfFont? embeddedFont;

      // =======================================================================
      // TRANSACTION METRIC TRACKERS
      // =======================================================================
      int totalModificationsMade = 0;
      double balanceAdjustmentDelta = 0.0; 
      
      double trueLastRowBalance = 0.0;
      double totalDebitAdjustment = 0.0;
      double totalCreditAdjustment = 0.0;

      final PdfColor exactBgColor = PdfColor(230, 255, 255);
      PdfStringFormat rightAlignFormat = PdfStringFormat()..alignment = PdfTextAlignment.right;
      double customWidth = 60.0;

      // --------------------------------------------------------
      // PASS 1: SCAN AND RECALCULATE INDIVIDUAL TRANSACTION ROWS
      // --------------------------------------------------------
      for (int i = 0; i < document.pages.count; i++) {
        List<TextLine> lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
        
        bool activeTargetLookout = false;

        for (int currentLineIdx = 0; currentLineIdx < lines.length; currentLineIdx++) {
          TextLine line = lines[currentLineIdx];
          String normalizedLineText = line.text.toLowerCase();

          if (line.bounds.top > 700 ||
              normalizedLineText.contains("opening balance") || 
              normalizedLineText.contains("closing bal") || 
              normalizedLineText.contains("statement summary") ||
              normalizedLineText.contains("computer generated") ||
              normalizedLineText.contains("require signature")) {
            continue;
          }

          if (normalizedLineText.contains("upi-santhoshi")) {
            activeTargetLookout = true;
          }

          TextWord? col4Word;
          TextWord? col5LedgerWord;

          // STRICT BOUNDING SEPARATION MATRIX
          for (TextWord word in line.wordCollection) {
            double leftX = word.bounds.left;
            
            if (leftX >= 415 && leftX <= 475) {
              col4Word = word; // Captured Debit
            } else if (leftX >= 495 && leftX <= 560) {
              col4Word = word; // Captured Credit (maps to same processor pipeline logic)
            } else if (leftX >= 575 && leftX <= 640) {
              col5LedgerWord = word; // True Running Balance Column
            }
          }

          if (embeddedFont == null) {
            try {
              final ByteData fontData = await rootBundle.load('assets/times.ttf');
              final Uint8List fontBytes = fontData.buffer.asUint8List();
              embeddedFont = PdfTrueTypeFont(fontBytes, 7.8);
            } catch (_) {
              embeddedFont = PdfStandardFont(PdfFontFamily.timesRoman, 8.5);
            }
          }

          if (col5LedgerWord != null) {
            String cleanLedgerStr = col5LedgerWord.text.replaceAll(',', '');
            double explicitLedgerBalance = double.tryParse(cleanLedgerStr) ?? 0.0;

            bool rowWasModified = false;
            double rowDeltaChange = 0.0;

            String rawWordText = col4Word != null ? col4Word.text.trim() : "";

            // RULE 1: Process Target UPI-SANTHOSHI Rows dynamically
            if (activeTargetLookout && col4Word != null) {
              String cleanOriginalDebitStr = col4Word.text.replaceAll(',', '');
              double originalDebitValue = double.tryParse(cleanOriginalDebitStr) ?? 0.0;

              document.pages[i].graphics.drawRectangle(
                brush: PdfSolidBrush(exactBgColor), 
                bounds: Rect.fromLTRB(col4Word.bounds.left - 2, col4Word.bounds.top - 1, col4Word.bounds.right + 2, col4Word.bounds.bottom + 1)
              );
              Rect col4PrintBounds = Rect.fromLTWH(col4Word.bounds.right - customWidth, col4Word.bounds.top + 1.5, customWidth, col4Word.bounds.height + 4);
              document.pages[i].graphics.drawString("150.00", embeddedFont!, brush: PdfSolidBrush(PdfColor(0, 0, 0)), bounds: col4PrintBounds, format: rightAlignFormat);

              // Fixed Math Delta calculation for Debit reductions
              rowDeltaChange = (originalDebitValue - 150.0); 
              balanceAdjustmentDelta += rowDeltaChange; 
              rowWasModified = true;
              totalDebitAdjustment += -rowDeltaChange; 
              
              activeTargetLookout = false; 
            }
            // RULE 2: Process CMA entries with dynamic date filtering logic
            else if (normalizedLineText.contains("cma") && col4Word != null) {
              String cleanOriginalVal = col4Word.text.replaceAll(',', '');
              double originalValue = double.tryParse(cleanOriginalVal) ?? 0.0;

              document.pages[i].graphics.drawRectangle(
                brush: PdfSolidBrush(exactBgColor), 
                bounds: Rect.fromLTRB(col4Word.bounds.left - 15, col4Word.bounds.top - 1, col4Word.bounds.right + 2, col4Word.bounds.bottom + 1)
              );
              Rect col4PrintBounds = Rect.fromLTWH(col4Word.bounds.right - customWidth - 0.5, col4Word.bounds.top + 1.5, customWidth, col4Word.bounds.height + 4);

              if (normalizedLineText.contains("27/02/26")) {
                document.pages[i].graphics.drawString("40,009.00", embeddedFont!, brush: PdfSolidBrush(PdfColor(0, 0, 0)), bounds: col4PrintBounds, format: rightAlignFormat);
                rowDeltaChange = (40009.0 - originalValue);
              } else {
                document.pages[i].graphics.drawString("50,160.00", embeddedFont!, brush: PdfSolidBrush(PdfColor(0, 0, 0)), bounds: col4PrintBounds, format: rightAlignFormat);
                rowDeltaChange = (50160.0 - originalValue);
              }

              balanceAdjustmentDelta += rowDeltaChange;
              rowWasModified = true;
              totalCreditAdjustment += rowDeltaChange;
            }

            trueLastRowBalance = explicitLedgerBalance + balanceAdjustmentDelta;

            if (balanceAdjustmentDelta != 0.0 || rowWasModified) {
              document.pages[i].graphics.drawRectangle(
                brush: PdfSolidBrush(exactBgColor), 
                bounds: Rect.fromLTRB(col5LedgerWord.bounds.left - 5, col5LedgerWord.bounds.top - 1, col5LedgerWord.bounds.right + 2, col5LedgerWord.bounds.bottom + 1)
              );
              RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
              String formattedBalance = trueLastRowBalance.toStringAsFixed(2).replaceAllMapped(reg, (Match match) => '${match[1]},');

              Rect col5PrintBounds = Rect.fromLTWH(col5LedgerWord.bounds.right - customWidth - 0.5, col5LedgerWord.bounds.top + 1.5, customWidth, col5LedgerWord.bounds.height + 4);
              document.pages[i].graphics.drawString(formattedBalance, embeddedFont!, brush: PdfSolidBrush(PdfColor(0, 0, 0)), bounds: col5PrintBounds, format: rightAlignFormat);
              
              totalModificationsMade++;
            }
          }
        }
      }

      // --------------------------------------------------------
      // PASS 2: INDEX-ANCHORED SUMMARY OVERWRITE ENGINE
      // --------------------------------------------------------
      int lastPageIndex = document.pages.count - 1;
      PdfPage summaryPage = document.pages[lastPageIndex];
      List<TextLine> finalPageLines = extractor.extractTextLines(startPageIndex: lastPageIndex, endPageIndex: lastPageIndex);

      for (int currentLineIndex = 0; currentLineIndex < finalPageLines.length; currentLineIndex++) {
        String lineText = finalPageLines[currentLineIndex].text.trim();

        if (lineText.contains("Opening Balance") && lineText.contains("Closing Bal")) {
          int numbersLineIndex = currentLineIndex + 1;
          
          if (numbersLineIndex < finalPageLines.length) {
            TextLine numbersLine = finalPageLines[numbersLineIndex];
            List<TextWord> words = numbersLine.wordCollection;

            if (words.length >= 6) {
              RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
              final PdfColor whiteBgColor = PdfColor(255, 255, 255);
              PdfStringFormat summaryAlignFormat = PdfStringFormat()..alignment = PdfTextAlignment.right;
              double summaryCustomWidth = 55.0; 

              TextWord summaryDebitWord = words[3];
              String cleanValDebit = summaryDebitWord.text.replaceAll(',', '');
              double originalDebitTotal = double.tryParse(cleanValDebit) ?? 0.0;
              double calculatedFinalDebits = originalDebitTotal + totalDebitAdjustment;
              String formattedDebits = calculatedFinalDebits.toStringAsFixed(2).replaceAllMapped(reg, (Match m) => '${m[1]},');

              summaryPage.graphics.drawRectangle(
                brush: PdfSolidBrush(whiteBgColor), 
                bounds: Rect.fromLTRB(summaryDebitWord.bounds.left - 12, summaryDebitWord.bounds.top - 4, summaryDebitWord.bounds.right + 20, summaryDebitWord.bounds.bottom + 4)
              );
              Rect printBoundsDebit = Rect.fromLTWH(summaryDebitWord.bounds.right - summaryCustomWidth - 1.0, summaryDebitWord.bounds.top + 1.5, summaryCustomWidth, summaryDebitWord.bounds.height + 4);
              summaryPage.graphics.drawString(formattedDebits, embeddedFont!, brush: PdfSolidBrush(PdfColor(0, 0, 0)), bounds: printBoundsDebit, format: summaryAlignFormat);

              TextWord summaryCreditWord = words[4];
              String cleanValCredit = summaryCreditWord.text.replaceAll(',', '');
              double originalCreditTotal = double.tryParse(cleanValCredit) ?? 0.0;
              double calculatedFinalCredits = originalCreditTotal + totalCreditAdjustment;
              String formattedCredits = calculatedFinalCredits.toStringAsFixed(2).replaceAllMapped(reg, (Match m) => '${m[1]},');

              summaryPage.graphics.drawRectangle(
                brush: PdfSolidBrush(whiteBgColor), 
                bounds: Rect.fromLTRB(summaryCreditWord.bounds.left - 12, summaryCreditWord.bounds.top - 4, summaryCreditWord.bounds.right + 20, summaryCreditWord.bounds.bottom + 4)
              );
              Rect printBoundsCredit = Rect.fromLTWH(summaryCreditWord.bounds.right - summaryCustomWidth - 1.0, summaryCreditWord.bounds.top + 1.5, summaryCustomWidth, summaryCreditWord.bounds.height + 4);
              summaryPage.graphics.drawString(formattedCredits, embeddedFont!, brush: PdfSolidBrush(PdfColor(0, 0, 0)), bounds: printBoundsCredit, format: summaryAlignFormat);

              TextWord summaryClosingWord = words[5];
              summaryPage.graphics.drawRectangle(
                brush: PdfSolidBrush(whiteBgColor), 
                bounds: Rect.fromLTRB(summaryClosingWord.bounds.left - 12, summaryClosingWord.bounds.top - 4, summaryClosingWord.bounds.right + 20, summaryClosingWord.bounds.bottom + 4)
              );
              String formattedClosing = trueLastRowBalance.toStringAsFixed(2).replaceAllMapped(reg, (Match m) => '${m[1]},');
              Rect printBoundsClosing = Rect.fromLTWH(summaryClosingWord.bounds.right - summaryCustomWidth - 1.0, summaryClosingWord.bounds.top + 1.5, summaryCustomWidth, summaryClosingWord.bounds.height + 4);
              summaryPage.graphics.drawString(formattedClosing, embeddedFont!, brush: PdfSolidBrush(PdfColor(0, 0, 0)), bounds: printBoundsClosing, format: summaryAlignFormat);
              
              totalModificationsMade++;
            }
          }
          break; 
        }
      }

      // 5. Build and lock raw bytes
      final List<int> bytes = await document.save();
      document.dispose();
      final Uint8List finalizedBytes = Uint8List.fromList(bytes);

      // 6. Dynamic Client Download Pipelines (Original Name Preserved)
      if (kIsWeb) {
        final blob = html.Blob([finalizedBytes], 'application/pdf', 'native');
        final url = html.Url.createObjectUrlFromBlob(blob);
        
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", originalFileName)
          ..style.display = 'none';
          
        html.document.body?.children.add(anchor);
        anchor.click();
        
        anchor.remove();
        html.Url.revokeObjectUrl(url);
        
        setState(() {
          _isProcessing = false;
          _statusMessage = "Success! Statement layout summary calculations applied perfectly.";
        });
      } else {
        final Directory? downloadsDir = await getDownloadsDirectory();
        final String outputPath = '${downloadsDir!.path}/$originalFileName';
        final File outputFile = File(outputPath);
        await outputFile.writeAsBytes(finalizedBytes);

        setState(() {
          _isProcessing = false;
          _statusMessage = "Success! Saved locally:\n$outputPath";
        });
      }

    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "An unexpected error occurred: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡ Fast PDF Auto-Editor'), 
        backgroundColor: Colors.blue.shade50,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_turned_in, size: 100, color: Colors.blueAccent.shade200),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 48),
              _isProcessing
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                        elevation: 2,
                      ),
                      onPressed: _processAndDownloadPdf,
                      icon: const Icon(Icons.file_upload, size: 24),
                      label: const Text("Upload & Process PDF", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}