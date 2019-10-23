// Copyright 2017 The Dawn Authors
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

#include "dawn_native/metal/TextureMTL.h"

#include "common/Platform.h"
#include "dawn_native/metal/DeviceMTL.h"

namespace dawn_native { namespace metal {

    namespace {
        bool UsageNeedsTextureView(wgpu::TextureUsage usage) {
            constexpr wgpu::TextureUsage kUsageNeedsTextureView =
                wgpu::TextureUsage::Storage | wgpu::TextureUsage::Sampled;
            return usage & kUsageNeedsTextureView;
        }

        MTLTextureUsage MetalTextureUsage(wgpu::TextureUsage usage) {
            MTLTextureUsage result = MTLTextureUsageUnknown;  // This is 0

            if (usage & (wgpu::TextureUsage::Storage)) {
                result |= MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
            }

            if (usage & (wgpu::TextureUsage::Sampled)) {
                result |= MTLTextureUsageShaderRead;
            }

            if (usage & (wgpu::TextureUsage::OutputAttachment)) {
                result |= MTLTextureUsageRenderTarget;
            }

            if (UsageNeedsTextureView(usage)) {
                result |= MTLTextureUsagePixelFormatView;
            }

            return result;
        }

        MTLTextureType MetalTextureType(wgpu::TextureDimension dimension,
                                        unsigned int arrayLayers,
                                        unsigned int sampleCount) {
            switch (dimension) {
                case wgpu::TextureDimension::e2D:
                    if (sampleCount > 1) {
                        ASSERT(arrayLayers == 1);
                        return MTLTextureType2DMultisample;
                    } else {
                        return (arrayLayers > 1) ? MTLTextureType2DArray : MTLTextureType2D;
                    }
                default:
                    UNREACHABLE();
            }
        }

        MTLTextureType MetalTextureViewType(wgpu::TextureViewDimension dimension,
                                            unsigned int sampleCount) {
            switch (dimension) {
                case wgpu::TextureViewDimension::e2D:
                    return (sampleCount > 1) ? MTLTextureType2DMultisample : MTLTextureType2D;
                case wgpu::TextureViewDimension::e2DArray:
                    return MTLTextureType2DArray;
                case wgpu::TextureViewDimension::Cube:
                    return MTLTextureTypeCube;
                case wgpu::TextureViewDimension::CubeArray:
                    return MTLTextureTypeCubeArray;
                default:
                    UNREACHABLE();
                    return MTLTextureType2D;
            }
        }

        bool RequiresCreatingNewTextureView(const TextureBase* texture,
                                            const TextureViewDescriptor* textureViewDescriptor) {
            if (texture->GetFormat().format != textureViewDescriptor->format) {
                return true;
            }

            if (texture->GetArrayLayers() != textureViewDescriptor->arrayLayerCount) {
                return true;
            }

            if (texture->GetNumMipLevels() != textureViewDescriptor->mipLevelCount) {
                return true;
            }

            switch (textureViewDescriptor->dimension) {
                case wgpu::TextureViewDimension::Cube:
                case wgpu::TextureViewDimension::CubeArray:
                    return true;
                default:
                    break;
            }

            return false;
        }

        ResultOrError<wgpu::TextureFormat> GetFormatEquivalentToIOSurfaceFormat(uint32_t format) {
            switch (format) {
                case 'RGBA':
                    return wgpu::TextureFormat::RGBA8Unorm;
                case 'BGRA':
                    return wgpu::TextureFormat::BGRA8Unorm;
                case '2C08':
                    return wgpu::TextureFormat::RG8Unorm;
                case 'L008':
                    return wgpu::TextureFormat::R8Unorm;
                default:
                    return DAWN_VALIDATION_ERROR("Unsupported IOSurface format");
            }
        }

#if defined(DAWN_PLATFORM_MACOS)
        MTLStorageMode kIOSurfaceStorageMode = MTLStorageModeManaged;
#elif defined(DAWN_PLATFORM_IOS)
        MTLStorageMode kIOSurfaceStorageMode = MTLStorageModePrivate;
#else
#    error "Unsupported Apple platform."
#endif
    }

    MTLPixelFormat MetalPixelFormat(wgpu::TextureFormat format) {
        switch (format) {
            case wgpu::TextureFormat::R8Unorm:
                return MTLPixelFormatR8Unorm;
            case wgpu::TextureFormat::R8Snorm:
                return MTLPixelFormatR8Snorm;
            case wgpu::TextureFormat::R8Uint:
                return MTLPixelFormatR8Uint;
            case wgpu::TextureFormat::R8Sint:
                return MTLPixelFormatR8Sint;

            case wgpu::TextureFormat::R16Uint:
                return MTLPixelFormatR16Uint;
            case wgpu::TextureFormat::R16Sint:
                return MTLPixelFormatR16Sint;
            case wgpu::TextureFormat::R16Float:
                return MTLPixelFormatR16Float;
            case wgpu::TextureFormat::RG8Unorm:
                return MTLPixelFormatRG8Unorm;
            case wgpu::TextureFormat::RG8Snorm:
                return MTLPixelFormatRG8Snorm;
            case wgpu::TextureFormat::RG8Uint:
                return MTLPixelFormatRG8Uint;
            case wgpu::TextureFormat::RG8Sint:
                return MTLPixelFormatRG8Sint;

            case wgpu::TextureFormat::R32Uint:
                return MTLPixelFormatR32Uint;
            case wgpu::TextureFormat::R32Sint:
                return MTLPixelFormatR32Sint;
            case wgpu::TextureFormat::R32Float:
                return MTLPixelFormatR32Float;
            case wgpu::TextureFormat::RG16Uint:
                return MTLPixelFormatRG16Uint;
            case wgpu::TextureFormat::RG16Sint:
                return MTLPixelFormatRG16Sint;
            case wgpu::TextureFormat::RG16Float:
                return MTLPixelFormatRG16Float;
            case wgpu::TextureFormat::RGBA8Unorm:
                return MTLPixelFormatRGBA8Unorm;
            case wgpu::TextureFormat::RGBA8UnormSrgb:
                return MTLPixelFormatRGBA8Unorm_sRGB;
            case wgpu::TextureFormat::RGBA8Snorm:
                return MTLPixelFormatRGBA8Snorm;
            case wgpu::TextureFormat::RGBA8Uint:
                return MTLPixelFormatRGBA8Uint;
            case wgpu::TextureFormat::RGBA8Sint:
                return MTLPixelFormatRGBA8Sint;
            case wgpu::TextureFormat::BGRA8Unorm:
                return MTLPixelFormatBGRA8Unorm;
            case wgpu::TextureFormat::BGRA8UnormSrgb:
                return MTLPixelFormatBGRA8Unorm_sRGB;
            case wgpu::TextureFormat::RGB10A2Unorm:
                return MTLPixelFormatRGB10A2Unorm;
            case wgpu::TextureFormat::RG11B10Float:
                return MTLPixelFormatRG11B10Float;

            case wgpu::TextureFormat::RG32Uint:
                return MTLPixelFormatRG32Uint;
            case wgpu::TextureFormat::RG32Sint:
                return MTLPixelFormatRG32Sint;
            case wgpu::TextureFormat::RG32Float:
                return MTLPixelFormatRG32Float;
            case wgpu::TextureFormat::RGBA16Uint:
                return MTLPixelFormatRGBA16Uint;
            case wgpu::TextureFormat::RGBA16Sint:
                return MTLPixelFormatRGBA16Sint;
            case wgpu::TextureFormat::RGBA16Float:
                return MTLPixelFormatRGBA16Float;

            case wgpu::TextureFormat::RGBA32Uint:
                return MTLPixelFormatRGBA32Uint;
            case wgpu::TextureFormat::RGBA32Sint:
                return MTLPixelFormatRGBA32Sint;
            case wgpu::TextureFormat::RGBA32Float:
                return MTLPixelFormatRGBA32Float;

            case wgpu::TextureFormat::Depth32Float:
                return MTLPixelFormatDepth32Float;
            case wgpu::TextureFormat::Depth24Plus:
                return MTLPixelFormatDepth32Float;
            case wgpu::TextureFormat::Depth24PlusStencil8:
                return MTLPixelFormatDepth32Float_Stencil8;

#if defined(DAWN_PLATFORM_MACOS)
            case wgpu::TextureFormat::BC1RGBAUnorm:
                return MTLPixelFormatBC1_RGBA;
            case wgpu::TextureFormat::BC1RGBAUnormSrgb:
                return MTLPixelFormatBC1_RGBA_sRGB;
            case wgpu::TextureFormat::BC2RGBAUnorm:
                return MTLPixelFormatBC2_RGBA;
            case wgpu::TextureFormat::BC2RGBAUnormSrgb:
                return MTLPixelFormatBC2_RGBA_sRGB;
            case wgpu::TextureFormat::BC3RGBAUnorm:
                return MTLPixelFormatBC3_RGBA;
            case wgpu::TextureFormat::BC3RGBAUnormSrgb:
                return MTLPixelFormatBC3_RGBA_sRGB;
            case wgpu::TextureFormat::BC4RSnorm:
                return MTLPixelFormatBC4_RSnorm;
            case wgpu::TextureFormat::BC4RUnorm:
                return MTLPixelFormatBC4_RUnorm;
            case wgpu::TextureFormat::BC5RGSnorm:
                return MTLPixelFormatBC5_RGSnorm;
            case wgpu::TextureFormat::BC5RGUnorm:
                return MTLPixelFormatBC5_RGUnorm;
            case wgpu::TextureFormat::BC6HRGBSfloat:
                return MTLPixelFormatBC6H_RGBFloat;
            case wgpu::TextureFormat::BC6HRGBUfloat:
                return MTLPixelFormatBC6H_RGBUfloat;
            case wgpu::TextureFormat::BC7RGBAUnorm:
                return MTLPixelFormatBC7_RGBAUnorm;
            case wgpu::TextureFormat::BC7RGBAUnormSrgb:
                return MTLPixelFormatBC7_RGBAUnorm_sRGB;
#endif

            default:
                UNREACHABLE();
        }
    }

    MaybeError ValidateIOSurfaceCanBeWrapped(const DeviceBase*,
                                             const TextureDescriptor* descriptor,
                                             IOSurfaceRef ioSurface,
                                             uint32_t plane) {
        // IOSurfaceGetPlaneCount can return 0 for non-planar IOSurfaces but we will treat
        // non-planar like it is a single plane.
        size_t surfacePlaneCount = std::max(size_t(1), IOSurfaceGetPlaneCount(ioSurface));
        if (plane >= surfacePlaneCount) {
            return DAWN_VALIDATION_ERROR("IOSurface plane doesn't exist");
        }

        if (descriptor->dimension != wgpu::TextureDimension::e2D) {
            return DAWN_VALIDATION_ERROR("IOSurface texture must be 2D");
        }

        if (descriptor->mipLevelCount != 1) {
            return DAWN_VALIDATION_ERROR("IOSurface mip level count must be 1");
        }

        if (descriptor->arrayLayerCount != 1) {
            return DAWN_VALIDATION_ERROR("IOSurface array layer count must be 1");
        }

        if (descriptor->sampleCount != 1) {
            return DAWN_VALIDATION_ERROR("IOSurface sample count must be 1");
        }

        if (descriptor->size.width != IOSurfaceGetWidthOfPlane(ioSurface, plane) ||
            descriptor->size.height != IOSurfaceGetHeightOfPlane(ioSurface, plane) ||
            descriptor->size.depth != 1) {
            return DAWN_VALIDATION_ERROR("IOSurface size doesn't match descriptor");
        }

        wgpu::TextureFormat ioSurfaceFormat;
        DAWN_TRY_ASSIGN(ioSurfaceFormat,
                        GetFormatEquivalentToIOSurfaceFormat(IOSurfaceGetPixelFormat(ioSurface)));
        if (descriptor->format != ioSurfaceFormat) {
            return DAWN_VALIDATION_ERROR("IOSurface format doesn't match descriptor");
        }

        return {};
    }

    MTLTextureDescriptor* CreateMetalTextureDescriptor(const TextureDescriptor* descriptor) {
        MTLTextureDescriptor* mtlDesc = [MTLTextureDescriptor new];
        mtlDesc.textureType = MetalTextureType(descriptor->dimension, descriptor->arrayLayerCount,
                                               descriptor->sampleCount);
        mtlDesc.usage = MetalTextureUsage(descriptor->usage);
        mtlDesc.pixelFormat = MetalPixelFormat(descriptor->format);

        mtlDesc.width = descriptor->size.width;
        mtlDesc.height = descriptor->size.height;
        mtlDesc.depth = descriptor->size.depth;

        mtlDesc.mipmapLevelCount = descriptor->mipLevelCount;
        mtlDesc.arrayLength = descriptor->arrayLayerCount;
        mtlDesc.storageMode = MTLStorageModePrivate;

        mtlDesc.sampleCount = descriptor->sampleCount;

        return mtlDesc;
    }

    Texture::Texture(Device* device, const TextureDescriptor* descriptor)
        : TextureBase(device, descriptor, TextureState::OwnedInternal) {
        MTLTextureDescriptor* mtlDesc = CreateMetalTextureDescriptor(descriptor);
        mMtlTexture = [device->GetMTLDevice() newTextureWithDescriptor:mtlDesc];
        [mtlDesc release];
    }

    Texture::Texture(Device* device, const TextureDescriptor* descriptor, id<MTLTexture> mtlTexture)
        : TextureBase(device, descriptor, TextureState::OwnedInternal), mMtlTexture(mtlTexture) {
        [mMtlTexture retain];
    }

    Texture::Texture(Device* device,
                     const TextureDescriptor* descriptor,
                     IOSurfaceRef ioSurface,
                     uint32_t plane)
        : TextureBase(device, descriptor, TextureState::OwnedInternal) {
        MTLTextureDescriptor* mtlDesc = CreateMetalTextureDescriptor(descriptor);
        mtlDesc.storageMode = kIOSurfaceStorageMode;
        mMtlTexture = [device->GetMTLDevice() newTextureWithDescriptor:mtlDesc
                                                             iosurface:ioSurface
                                                                 plane:plane];
        [mtlDesc release];
    }

    Texture::~Texture() {
        DestroyInternal();
    }

    void Texture::DestroyImpl() {
        if (GetTextureState() == TextureState::OwnedInternal) {
            [mMtlTexture release];
            mMtlTexture = nil;
        }
    }

    id<MTLTexture> Texture::GetMTLTexture() {
        return mMtlTexture;
    }

    TextureView::TextureView(TextureBase* texture, const TextureViewDescriptor* descriptor)
        : TextureViewBase(texture, descriptor) {
        id<MTLTexture> mtlTexture = ToBackend(texture)->GetMTLTexture();

        if (!UsageNeedsTextureView(texture->GetUsage())) {
            mMtlTextureView = nil;
        } else if (!RequiresCreatingNewTextureView(texture, descriptor)) {
            mMtlTextureView = [mtlTexture retain];
        } else {
            MTLPixelFormat format = MetalPixelFormat(descriptor->format);
            MTLTextureType textureViewType =
                MetalTextureViewType(descriptor->dimension, texture->GetSampleCount());
            auto mipLevelRange = NSMakeRange(descriptor->baseMipLevel, descriptor->mipLevelCount);
            auto arrayLayerRange =
                NSMakeRange(descriptor->baseArrayLayer, descriptor->arrayLayerCount);

            mMtlTextureView = [mtlTexture newTextureViewWithPixelFormat:format
                                                            textureType:textureViewType
                                                                 levels:mipLevelRange
                                                                 slices:arrayLayerRange];
        }
    }

    TextureView::~TextureView() {
        [mMtlTextureView release];
    }

    id<MTLTexture> TextureView::GetMTLTexture() {
        ASSERT(mMtlTextureView != nil);
        return mMtlTextureView;
    }
}}  // namespace dawn_native::metal
