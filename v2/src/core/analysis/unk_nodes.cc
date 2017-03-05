//
// Created by Arseny Tolmachev on 2017/03/05.
//

#include "unk_nodes.h"
#include "core/core.h"
#include "dic_reader.h"
#include "unk_nodes_creator.h"
#include "util/stl_util.h"

namespace jumanpp {
namespace core {
namespace analysis {

class UnkMakerFactory {
  util::memory::Manager mgr;
  std::unique_ptr<util::memory::ManagedAllocatorCore> mac;
  DicReader rdr;
  dic::DictionaryEntries entries;
  const features::FeatureRuntimeInfo& fri;

 public:
  UnkMakerFactory(const CoreHolder& core)
      : mgr{16 * 1024},
        mac{mgr.core()},
        rdr{mac.get(), core.dic()},
        entries{core.dic().entries()},
        fri{core.runtime().features} {}

  Status handlePrefixIndex(const UnkMakerInfo& info,
                           UnkNodeConfig* pConfig) const {
    for (auto& x : info.features) {
      if (x.type == spec::UnkFeatureType::NotPrefixOfDicWord) {
        for (int i = 0; i < fri.placeholderMapping.size(); ++i) {
          if (fri.placeholderMapping[i] == x.reference) {
            pConfig->notPrefixIndex = i;
          }
        }
        if (pConfig->notPrefixIndex == -1) {
          return Status::InvalidState()
                 << "could not find placeholder for notPrefix feature of "
                 << info.name;
        }
      }
    }
    return Status::Ok();
  }

  Status make(const UnkMakersInfo& info, UnkMakers* result) const {
    for (auto& x : info.makers) {
      switch (x.type) {
        case spec::UnkMakerType::Chunking: {
          UnkNodeConfig cfg{rdr.readEntry(EntryPtr{x.patternPtr})};
          util::copy(x.output, cfg.replaceWithSurface);
          handlePrefixIndex(x, &cfg);
          result->stage1.emplace_back(
              new ChunkingUnkMaker{entries, x.charClass, std::move(cfg)});
          break;
        }
        case spec::UnkMakerType::Single: {
          UnkNodeConfig cfg{rdr.readEntry(EntryPtr{x.patternPtr})};
          util::copy(x.output, cfg.replaceWithSurface);
          handlePrefixIndex(x, &cfg);
          result->stage1.emplace_back(
              new SingleUnkMaker{entries, x.charClass, std::move(cfg)});
          break;
        }
        default:
          return Status::NotImplemented() << x.name
                                          << ": unk is not implemented";
      }
    }
    return Status::Ok();
  }
};

Status makeMakers(const CoreHolder& core, const UnkMakersInfo& info,
                  UnkMakers* result) {
  UnkMakerFactory factory{core};
  return factory.make(info, result);
}

}  // analysis
}  // core
}  // jumanpp