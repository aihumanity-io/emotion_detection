#include "emotion_onnx_runtime_adapter.h"

#if EMOTION_ENABLE_ONNX_RUNTIME
#include <onnxruntime_c_api.h>

#include <algorithm>
#include <cstring>
#endif

namespace emotion {
namespace native_sdk {

#if EMOTION_ENABLE_ONNX_RUNTIME
namespace {

RuntimeLoadResult runtime_error(const std::string& error) {
  RuntimeLoadResult result;
  result.error = error;
  return result;
}

RuntimePredictResult predict_error(const std::string& error) {
  RuntimePredictResult result;
  result.error = error;
  return result;
}

std::string status_message(const OrtApi* api, OrtStatus* status) {
  if (status == nullptr) {
    return "";
  }
  const char* message = api->GetErrorMessage(status);
  std::string result = message == nullptr ? "onnx runtime error" : message;
  api->ReleaseStatus(status);
  return result;
}

}  // namespace

struct OnnxRuntimeSession::Impl {
  const OrtApi* api = nullptr;
  OrtEnv* env = nullptr;
  OrtSessionOptions* options = nullptr;
  OrtSession* session = nullptr;
  OrtMemoryInfo* memory_info = nullptr;
  std::string input_name;
  std::string output_name;
};

OnnxRuntimeSession::OnnxRuntimeSession() : impl_(new Impl()) {
  impl_->api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
}

OnnxRuntimeSession::~OnnxRuntimeSession() {
  unload();
  if (impl_->memory_info != nullptr) {
    impl_->api->ReleaseMemoryInfo(impl_->memory_info);
    impl_->memory_info = nullptr;
  }
  if (impl_->options != nullptr) {
    impl_->api->ReleaseSessionOptions(impl_->options);
    impl_->options = nullptr;
  }
  if (impl_->env != nullptr) {
    impl_->api->ReleaseEnv(impl_->env);
    impl_->env = nullptr;
  }
}

RuntimeLoadResult OnnxRuntimeSession::load(
    const std::vector<uint8_t>& model_bytes) {
  if (model_bytes.empty()) {
    return runtime_error("missing model bytes");
  }
  unload();

  OrtStatus* status = impl_->api->CreateEnv(ORT_LOGGING_LEVEL_WARNING,
                                            "emotion-sdk", &impl_->env);
  if (status != nullptr) {
    return runtime_error(status_message(impl_->api, status));
  }
  status = impl_->api->CreateSessionOptions(&impl_->options);
  if (status != nullptr) {
    return runtime_error(status_message(impl_->api, status));
  }
  status = impl_->api->SetSessionGraphOptimizationLevel(
      impl_->options, ORT_ENABLE_BASIC);
  if (status != nullptr) {
    return runtime_error(status_message(impl_->api, status));
  }
  status = impl_->api->CreateSessionFromArray(
      impl_->env, model_bytes.data(), model_bytes.size(), impl_->options,
      &impl_->session);
  if (status != nullptr) {
    return runtime_error(status_message(impl_->api, status));
  }
  status = impl_->api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault,
                                           &impl_->memory_info);
  if (status != nullptr) {
    return runtime_error(status_message(impl_->api, status));
  }

  OrtAllocator* allocator = nullptr;
  status = impl_->api->GetAllocatorWithDefaultOptions(&allocator);
  if (status != nullptr) {
    return runtime_error(status_message(impl_->api, status));
  }

  char* input_name = nullptr;
  status = impl_->api->SessionGetInputName(impl_->session, 0, allocator,
                                           &input_name);
  if (status != nullptr) {
    return runtime_error(status_message(impl_->api, status));
  }
  impl_->input_name = input_name;
  allocator->Free(allocator, input_name);

  char* output_name = nullptr;
  status = impl_->api->SessionGetOutputName(impl_->session, 0, allocator,
                                            &output_name);
  if (status != nullptr) {
    return runtime_error(status_message(impl_->api, status));
  }
  impl_->output_name = output_name;
  allocator->Free(allocator, output_name);

  RuntimeLoadResult result;
  result.ok = true;
  return result;
}

RuntimeLoadResult OnnxRuntimeSession::warmup() {
  if (impl_->session == nullptr) {
    return runtime_error("onnx runtime not loaded");
  }
  RuntimeLoadResult result;
  result.ok = true;
  return result;
}

RuntimePredictResult OnnxRuntimeSession::predict(const FloatTensor& input) {
  if (impl_->session == nullptr || impl_->memory_info == nullptr) {
    return predict_error("onnx runtime not loaded");
  }
  if (input.values.empty() || input.shape.empty()) {
    return predict_error("missing input tensor");
  }

  OrtValue* input_tensor = nullptr;
  OrtStatus* status = impl_->api->CreateTensorWithDataAsOrtValue(
      impl_->memory_info, const_cast<float*>(input.values.data()),
      input.values.size() * sizeof(float), input.shape.data(),
      input.shape.size(), ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor);
  if (status != nullptr) {
    return predict_error(status_message(impl_->api, status));
  }

  const char* input_names[] = {impl_->input_name.c_str()};
  const char* output_names[] = {impl_->output_name.c_str()};
  OrtValue* output_tensor = nullptr;
  status = impl_->api->Run(impl_->session, nullptr, input_names, &input_tensor,
                           1, output_names, 1, &output_tensor);
  impl_->api->ReleaseValue(input_tensor);
  if (status != nullptr) {
    return predict_error(status_message(impl_->api, status));
  }

  float* output_data = nullptr;
  status = impl_->api->GetTensorMutableData(output_tensor,
                                           reinterpret_cast<void**>(&output_data));
  if (status != nullptr) {
    impl_->api->ReleaseValue(output_tensor);
    return predict_error(status_message(impl_->api, status));
  }

  OrtTensorTypeAndShapeInfo* shape_info = nullptr;
  status = impl_->api->GetTensorTypeAndShape(output_tensor, &shape_info);
  if (status != nullptr) {
    impl_->api->ReleaseValue(output_tensor);
    return predict_error(status_message(impl_->api, status));
  }
  size_t element_count = 0;
  status = impl_->api->GetTensorShapeElementCount(shape_info, &element_count);
  impl_->api->ReleaseTensorTypeAndShapeInfo(shape_info);
  if (status != nullptr) {
    impl_->api->ReleaseValue(output_tensor);
    return predict_error(status_message(impl_->api, status));
  }

  RuntimePredictResult result;
  result.ok = true;
  result.logits.assign(output_data, output_data + element_count);
  impl_->api->ReleaseValue(output_tensor);
  return result;
}

void OnnxRuntimeSession::unload() {
  if (impl_->session != nullptr) {
    impl_->api->ReleaseSession(impl_->session);
    impl_->session = nullptr;
  }
}

bool onnx_runtime_available() {
  return true;
}

#else

struct OnnxRuntimeSession::Impl {};

OnnxRuntimeSession::OnnxRuntimeSession() : impl_(new Impl()) {}

OnnxRuntimeSession::~OnnxRuntimeSession() {}

RuntimeLoadResult OnnxRuntimeSession::load(
    const std::vector<uint8_t>& /*model_bytes*/) {
  RuntimeLoadResult result;
  result.error = "onnx runtime adapter not linked";
  return result;
}

RuntimeLoadResult OnnxRuntimeSession::warmup() {
  RuntimeLoadResult result;
  result.error = "onnx runtime adapter not linked";
  return result;
}

RuntimePredictResult OnnxRuntimeSession::predict(const FloatTensor& /*input*/) {
  RuntimePredictResult result;
  result.error = "onnx runtime adapter not linked";
  return result;
}

void OnnxRuntimeSession::unload() {}

bool onnx_runtime_available() {
  return false;
}

#endif

}  // namespace native_sdk
}  // namespace emotion
