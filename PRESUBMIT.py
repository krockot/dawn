# Copyright 2018 The Dawn Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
import platform
import subprocess

USE_PYTHON3 = True


def _DoCommonChecks(input_api, output_api):
    results = []
    results.extend(
        input_api.canned_checks.CheckChangedLUCIConfigs(input_api, output_api))
    results.extend(
        input_api.canned_checks.CheckPatchFormatted(input_api,
                                                    output_api,
                                                    check_python=True))
    return results


def CheckChangeOnUpload(input_api, output_api):
    return _DoCommonChecks(input_api, output_api)


def CheckChangeOnCommit(input_api, output_api):
    return _DoCommonChecks(input_api, output_api)
