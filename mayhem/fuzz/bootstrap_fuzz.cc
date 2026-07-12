//
// In-process libFuzzer harness for the jumandic dictionary bootstrap code path.
//
// Mirrors src/jumandic/main/bootstrap.cc's importDictionary(): it feeds the fuzz
// input as the raw JumanDIC CSV and drives the same DictionaryBuilder.importCsv()
// + DictionaryHolder.load() pipeline that the jpp-jumandic-bootstrap CLI exercised.
//
// Built with -fsanitize=fuzzer so Mayhem runs it in libFuzzer mode and reads
// SanitizerCoverage edges reliably (the raw-file CLI reported 0 edges under Mayhem
// once ASan-instrumented). Target NAME jpp-jumandic-bootstrap is preserved for
// run-history parity.
//
#include <cstddef>
#include <cstdint>

#include "core/dic/dic_builder.h"
#include "core/dic/dictionary.h"
#include "jumandic/shared/jumandic_spec.h"
#include "util/string_piece.h"

using namespace jumanpp;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  StringPiece csv{reinterpret_cast<const char *>(data), size};

  core::spec::AnalysisSpec spec;
  if (!jumandic::SpecFactory::makeSpec(&spec)) {
    return 0;
  }

  core::dic::DictionaryBuilder builder;
  if (!builder.importSpec(&spec)) {
    return 0;
  }
  if (!builder.importCsv("fuzz", csv)) {
    return 0;
  }

  core::dic::DictionaryHolder holder;
  (void)holder.load(builder.result());
  return 0;
}
