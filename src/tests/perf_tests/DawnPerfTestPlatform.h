// Copyright 2019 The Dawn Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef TESTS_PERFTESTS_DAWNPERFTESTPLATFORM_H_
#define TESTS_PERFTESTS_DAWNPERFTESTPLATFORM_H_

#include <dawn_platform/DawnPlatform.h>

#include <memory>
#include <vector>

namespace utils {
    class Timer;
}

class DawnPerfTestPlatform : public dawn_platform::Platform {
  public:
    // These are trace events according to Google's "Trace Event Format".
    // See https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU
    // Only a subset of the properties are implemented.
    struct TraceEvent final {
        TraceEvent() {
        }
        TraceEvent(char phaseIn,
                   const char* categoryNameIn,
                   const char* nameIn,
                   uint64_t idIn,
                   double timestampIn)
            : phase(phaseIn),
              categoryName(categoryNameIn),
              name(nameIn),
              id(idIn),
              timestamp(timestampIn) {
        }

        char phase = 0;
        const char* categoryName = nullptr;
        const char* name = nullptr;
        uint64_t id = 0;
        double timestamp = 0;
    };

    explicit DawnPerfTestPlatform(bool enableTracing);
    ~DawnPerfTestPlatform() override;

    void EnableTraceEventRecording(bool enable);
    const std::vector<TraceEvent>& GetTraceEventBuffer() const;

  private:
    const unsigned char* GetTraceCategoryEnabledFlag(const char* name) override;

    double MonotonicallyIncreasingTime() override;

    uint64_t AddTraceEvent(char phase,
                           const unsigned char* categoryGroupEnabled,
                           const char* name,
                           uint64_t id,
                           double timestamp,
                           int numArgs,
                           const char** argNames,
                           const unsigned char* argTypes,
                           const uint64_t* argValues,
                           unsigned char flags) override;

    bool mEnableTracing = false;
    bool mRecordTraceEvents = false;
    std::unique_ptr<utils::Timer> mTimer;

    // Trace event record.
    std::vector<TraceEvent> mTraceEventBuffer;
};

#endif  // TESTS_PERFTESTS_DAWNPERFTESTPLATFORM_H_
