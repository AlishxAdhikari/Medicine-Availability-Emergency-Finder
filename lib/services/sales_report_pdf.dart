import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'owner_sales_log.dart';

/// Builds and previews/shares professional PDF sales reports and tax invoices.
class SalesReportPdf {
  SalesReportPdf._();
  static final SalesReportPdf instance = SalesReportPdf._();

  static final _green = PdfColor.fromInt(0xFF0B6B4F);
  static final _lightGrey = PdfColor.fromInt(0xFFF4F7F6);
  static final _border = PdfColor.fromInt(0xFFBDBDBD);

  String _fmtDate(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDateTime(DateTime t) => '${_fmtDate(t)}  ${_fmtTime(t)}';

  Future<void> shareDayReport({
    required String pharmacyName,
    required DateTime dayStart,
    required List<SaleRecord> sales,
  }) async {
    final store = pharmacyName.isEmpty ? 'Pharmacy' : pharmacyName;
    final dateStr = _fmtDate(dayStart);
    final totalRevenue = sales.fold<double>(0, (s, r) => s + r.total);
    final totalUnits = sales.fold<int>(0, (s, r) => s + r.unitCount);
    final totalBills = sales.length;

    final byCashier = <String, double>{};
    final unitsByCashier = <String, int>{};
    for (final s in sales) {
      final who = s.cashier.isEmpty ? 'Owner / POS' : s.cashier;
      byCashier[who] = (byCashier[who] ?? 0) + s.total;
      unitsByCashier[who] = (unitsByCashier[who] ?? 0) + s.unitCount;
    }

    final doc = pw.Document(
      title: 'Daily Sales Report — $dateStr',
      author: store,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => _header(store, 'DAILY SALES REPORT', dateStr),
        footer: (ctx) => _footer(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 12),
          _summaryBox([
            ('Bills', '$totalBills'),
            ('Units sold', '$totalUnits'),
            ('Total revenue', 'Rs ${totalRevenue.toStringAsFixed(2)}'),
            ('Date', dateStr),
          ]),
          pw.SizedBox(height: 16),
          _sectionTitle('Sales by cashier / user'),
          if (byCashier.isEmpty)
            pw.Text('No sales recorded for this day.',
                style: const pw.TextStyle(fontSize: 10))
          else
            _table(
              headers: ['Cashier / User', 'Units', 'Revenue (Rs)'],
              rows: (byCashier.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value)))
                  .map((e) => [
                        e.key,
                        '${unitsByCashier[e.key] ?? 0}',
                        e.value.toStringAsFixed(2),
                      ])
                  .toList(),
            ),
          pw.SizedBox(height: 18),
          _sectionTitle('Detailed bills (customer · items · time)'),
          if (sales.isEmpty)
            pw.Text('No completed sales with customer details for this day.',
                style: const pw.TextStyle(fontSize: 10))
          else
            ...sales.map(_saleBlock),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'Sales_Report_$dateStr.pdf',
    );
  }

  Future<void> shareAnalyticsReport({
    required String pharmacyName,
    required List<SaleRecord> sales,
    required DateTime generatedAt,
  }) async {
    final store = pharmacyName.isEmpty ? 'Pharmacy' : pharmacyName;
    final totalRevenue = sales.fold<double>(0, (s, r) => s + r.total);
    final totalUnits = sales.fold<int>(0, (s, r) => s + r.unitCount);

    final byMed = <String, int>{};
    final revByMed = <String, double>{};
    for (final s in sales) {
      for (final l in s.lines) {
        byMed[l.medicineName] = (byMed[l.medicineName] ?? 0) + l.quantity;
        revByMed[l.medicineName] =
            (revByMed[l.medicineName] ?? 0) + l.lineTotal;
      }
    }
    final topMeds = byMed.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final byCashier = <String, double>{};
    for (final s in sales) {
      final who = s.cashier.isEmpty ? 'Owner / POS' : s.cashier;
      byCashier[who] = (byCashier[who] ?? 0) + s.total;
    }
    final cashierRank = byCashier.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final byCustomer = <String, double>{};
    for (final s in sales) {
      final key = '${s.customerName} (${s.customerPhone})';
      byCustomer[key] = (byCustomer[key] ?? 0) + s.total;
    }
    final topCustomers = byCustomer.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final doc = pw.Document(
      title: 'Sales Analytics Report',
      author: store,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => _header(
          store,
          'SALES ANALYTICS REPORT',
          _fmtDateTime(generatedAt),
        ),
        footer: (ctx) => _footer(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 12),
          _summaryBox([
            ('Total bills', '${sales.length}'),
            ('Units sold', '$totalUnits'),
            ('Total revenue', 'Rs ${totalRevenue.toStringAsFixed(2)}'),
            ('Generated', _fmtDate(generatedAt)),
          ]),
          pw.SizedBox(height: 16),
          _sectionTitle('Top cashiers'),
          if (cashierRank.isEmpty)
            pw.Text('No data', style: const pw.TextStyle(fontSize: 10))
          else
            _table(
              headers: ['#', 'Cashier / User', 'Revenue (Rs)'],
              rows: cashierRank
                  .take(10)
                  .toList()
                  .asMap()
                  .entries
                  .map((e) => [
                        '${e.key + 1}',
                        e.value.key,
                        e.value.value.toStringAsFixed(2),
                      ])
                  .toList(),
            ),
          pw.SizedBox(height: 16),
          _sectionTitle('Top selling medicines'),
          if (topMeds.isEmpty)
            pw.Text('No data', style: const pw.TextStyle(fontSize: 10))
          else
            _table(
              headers: ['Medicine', 'Units', 'Revenue (Rs)'],
              rows: topMeds
                  .take(15)
                  .map((e) => [
                        e.key,
                        '${e.value}',
                        (revByMed[e.key] ?? 0).toStringAsFixed(2),
                      ])
                  .toList(),
            ),
          pw.SizedBox(height: 16),
          _sectionTitle('Top customers'),
          if (topCustomers.isEmpty)
            pw.Text('No data', style: const pw.TextStyle(fontSize: 10))
          else
            _table(
              headers: ['Customer', 'Spend (Rs)'],
              rows: topCustomers
                  .take(15)
                  .map((e) => [e.key, e.value.toStringAsFixed(2)])
                  .toList(),
            ),
          pw.SizedBox(height: 16),
          _sectionTitle('Recent bills'),
          ...sales.take(20).map(_saleBlock),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'Sales_Analytics_${_fmtDate(generatedAt)}.pdf',
    );
  }

  /// Thermal-style TAX INVOICE PDF for a single customer purchase.
  Future<void> shareTaxInvoice({
    required String pharmacyName,
    String address = '',
    String vatNumber = '',
    required String billNo,
    required DateTime time,
    required String cashier,
    required String customerName,
    required String customerPhone,
    String membership = '',
    required List<SaleLine> lines,
    double discountPercent = 0,
    double vatPercent = 13,
  }) async {
    final store = pharmacyName.isEmpty ? 'PHARMACY' : pharmacyName;
    final subtotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);
    final discountAmt = subtotal * (discountPercent / 100);
    final taxable = subtotal - discountAmt;
    final vatAmt = taxable * (vatPercent / 100);
    final total = taxable + vatAmt;

    final h12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final ampm = time.hour >= 12 ? 'PM' : 'AM';
    final dateDisplay =
        '${time.month}/${time.day}/${time.year} ${h12.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $ampm';

    final doc = pw.Document(title: 'Tax Invoice $billNo', author: store);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 120, vertical: 40),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  store.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (address.isNotEmpty)
                pw.Center(
                  child: pw.Text(address,
                      style: const pw.TextStyle(fontSize: 9)),
                ),
              if (vatNumber.isNotEmpty)
                pw.Center(
                  child: pw.Text('VAT #: $vatNumber',
                      style: const pw.TextStyle(fontSize: 9)),
                ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1),
              pw.Center(
                child: pw.Text(
                  'TAX INVOICE',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 6),
              pw.Text('INV: $billNo', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('DATE: $dateDisplay',
                  style: const pw.TextStyle(fontSize: 9)),
              if (cashier.isNotEmpty)
                pw.Text('CASHIER: $cashier',
                    style: const pw.TextStyle(fontSize: 9)),
              pw.Text('CUSTOMER: $customerName',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text('PHONE: $customerPhone',
                  style: const pw.TextStyle(fontSize: 9)),
              if (membership.isNotEmpty)
                pw.Text('MEMBER: $membership',
                    style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.8),
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text('ITEM',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(
                    width: 28,
                    child: pw.Text('QTY',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(
                    width: 40,
                    child: pw.Text('RATE',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(
                    width: 48,
                    child: pw.Text('AMT',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
              pw.Divider(thickness: 0.5),
              ...lines.map((l) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text(l.medicineName,
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.SizedBox(
                        width: 28,
                        child: pw.Text('${l.quantity}',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.SizedBox(
                        width: 40,
                        child: pw.Text(l.unitPrice.toStringAsFixed(0),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.SizedBox(
                        width: 48,
                        child: pw.Text(l.lineTotal.toStringAsFixed(2),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                    ],
                  ),
                );
              }),
              pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
              _invRow('SUBTOTAL:', subtotal.toStringAsFixed(2)),
              if (discountPercent > 0)
                _invRow('DISC (${discountPercent.toStringAsFixed(0)}%):',
                    '-${discountAmt.toStringAsFixed(2)}'),
              if (vatPercent > 0)
                _invRow('VAT (${vatPercent.toStringAsFixed(0)}%):',
                    vatAmt.toStringAsFixed(2)),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL:',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text(total.toStringAsFixed(2),
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: billNo,
                  width: 140,
                  height: 36,
                  drawText: false,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child:
                    pw.Text(billNo, style: const pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 14),
              pw.Center(
                child: pw.Text(
                  'THANK YOU FOR YOUR VISIT',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text('Get well soon.',
                    style: const pw.TextStyle(fontSize: 8)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'Invoice_$billNo.pdf',
    );
  }

  pw.Widget _invRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _header(String store, String title, String subtitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          color: _green,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                store.toUpperCase(),
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                title,
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 11),
              ),
              pw.Text(
                subtitle,
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Divider(color: _border, thickness: 0.5),
      ],
    );
  }

  pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'Page ${ctx.pageNumber} of ${ctx.pagesCount}  ·  Confidential',
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }

  pw.Widget _sectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: _green,
        ),
      ),
    );
  }

  pw.Widget _summaryBox(List<(String, String)> items) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _lightGrey,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _border, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: items
            .map(
              (e) => pw.Column(
                children: [
                  pw.Text(e.$2,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.Text(e.$1,
                      style: pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(color: _green),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      border: pw.TableBorder.all(color: _border, width: 0.4),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );
  }

  pw.Widget _saleBlock(SaleRecord s) {
    final member = s.membership != 'NONE' && s.membership.isNotEmpty
        ? ' · ${s.membership}${s.membershipId.isNotEmpty ? ' (${s.membershipId})' : ''}'
        : '';
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Bill ${s.billNo}',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 10, color: _green),
              ),
              pw.Text(
                _fmtDateTime(s.time),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Customer: ${s.customerName}  ·  ${s.customerPhone}$member',
            style: const pw.TextStyle(fontSize: 9),
          ),
          if (s.cashier.isNotEmpty)
            pw.Text('Cashier: ${s.cashier}',
                style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 4),
          _table(
            headers: ['Medicine', 'Qty', 'Unit', 'Amount'],
            rows: s.lines
                .map((l) => [
                      l.medicineName,
                      '${l.quantity}',
                      l.unitPrice.toStringAsFixed(2),
                      l.lineTotal.toStringAsFixed(2),
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 4),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'TOTAL: Rs ${s.total.toStringAsFixed(2)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
