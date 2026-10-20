#!/bin/sh
# Build one report per student (REPORT_FOR=0 G Sivakumar, 1 Kriti Sahana V) and
# convert each to PDF. Two passes: the first render gives the page numbers that
# pages.py writes into pages_<n>.json for the TOC and lists.
set -e
cd "$(dirname "$0")"
for n in 0 1; do
  out=$(REPORT_FOR=$n python3 -c "import content as C; print('Final_Report_' + C.ME[0].title().replace(' ', '_'))")
  [ -f pages_$n.json ] || echo '{}' > pages_$n.json
  for pass in 1 2; do
    REPORT_FOR=$n python3 build.py pages_$n.json >/dev/null
    soffice --headless --convert-to pdf "$out.docx" >/dev/null 2>&1
    REPORT_FOR=$n python3 pages.py "$out.pdf" pages_$n.json
  done
  echo "$out: $(pdfinfo "$out.pdf" | grep Pages)"
done
