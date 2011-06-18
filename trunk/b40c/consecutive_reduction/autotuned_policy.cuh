/******************************************************************************
 * 
 * Copyright 2010-2011 Duane Merrill
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License. 
 * 
 * For more information, see our Google Code project site: 
 * http://code.google.com/p/back40computing/
 * 
 ******************************************************************************/

/******************************************************************************
 * Autotuned consecutive reduction policy
 ******************************************************************************/

#pragma once

#include <b40c/util/cuda_properties.cuh>
#include <b40c/util/io/modified_load.cuh>
#include <b40c/util/io/modified_store.cuh>

#include <b40c/consecutive_reduction/upsweep/kernel.cuh>
#include <b40c/consecutive_reduction/spine/kernel.cuh>
#include <b40c/consecutive_reduction/downsweep/kernel.cuh>
#include <b40c/consecutive_reduction/single/kernel.cuh>
#include <b40c/consecutive_reduction/policy.cuh>


namespace b40c {
namespace consecutive_reduction {


/******************************************************************************
 * Genre enumerations to classify problems by
 ******************************************************************************/

/**
 * Enumeration of problem-size genres that we may have tuned for
 */
enum ProbSizeGenre
{
	UNKNOWN_SIZE = -1,			// Not actually specialized on: the enactor should use heuristics to select another size genre
	SMALL_SIZE,					// Tuned @ 128KB input
	LARGE_SIZE					// Tuned @ 128MB input
};


/**
 * Enumeration of architecture-family genres that we have tuned for below
 */
enum ArchGenre
{
	SM20 	= 200,
	SM13	= 130,
	SM10	= 100
};


/**
 * Enumeration of type size genres
 */
enum TypeSizeGenre
{
	TINY_TYPE,
	SMALL_TYPE,
	MEDIUM_TYPE,
	LARGE_TYPE
};


/******************************************************************************
 * Classifiers for identifying classification genres
 ******************************************************************************/

/**
 * Classifies a given CUDA_ARCH into an architecture-family genre
 */
template <int CUDA_ARCH>
struct ArchClassifier
{
	static const ArchGenre GENRE 			=	// (CUDA_ARCH < SM13) ? SM10 :			// Haven't tuned for SM1.0 yet
												(CUDA_ARCH < SM20) ? SM13 : SM20;
};


/**
 * Classifies the problem type(s) into a type-size genre
 */
template <typename ProblemType>
struct TypeSizeClassifier
{
	static const int KEYS_ROUNDED_SIZE		= 1 << util::Log2<sizeof(typename ProblemType::KeyType)>::VALUE;	// Round up to the nearest arch subword
	static const int VALUES_ROUNDED_SIZE	= 1 << util::Log2<sizeof(typename ProblemType::ValueType)>::VALUE;
	static const int MAX_ROUNDED_SIZE		= B40C_MAX(KEYS_ROUNDED_SIZE, VALUES_ROUNDED_SIZE);

	static const TypeSizeGenre GENRE 		= (MAX_ROUNDED_SIZE < 8) ? MEDIUM_TYPE : LARGE_TYPE;
};


/**
 * Classifies the pointer type into a type-size genre
 */
template <typename ProblemType>
struct PointerSizeClassifier
{
	static const TypeSizeGenre GENRE 		= (sizeof(typename ProblemType::SizeT) < 8) ? MEDIUM_TYPE : LARGE_TYPE;
};


/******************************************************************************
 * Autotuned genre and specializations
 ******************************************************************************/

/**
 * Autotuning policy genre, to be specialized
 */
template <
	// Problem and machine types
	typename ProblemType,
	int CUDA_ARCH,

	// Genres to specialize upon
	ProbSizeGenre PROB_SIZE_GENRE,
	ArchGenre ARCH_GENRE = ArchClassifier<CUDA_ARCH>::GENRE,
	TypeSizeGenre TYPE_SIZE_GENRE = TypeSizeClassifier<ProblemType>::GENRE,
	TypeSizeGenre POINTER_SIZE_GENRE = PointerSizeClassifier<ProblemType>::GENRE>
struct AutotunedGenre;


//-----------------------------------------------------------------------------
// SM2.0 specializations(s)
//-----------------------------------------------------------------------------

// Temporary
template <
	typename ProblemType,
	int CUDA_ARCH,
	ProbSizeGenre _PROB_SIZE_GENRE,
	TypeSizeGenre TYPE_SIZE_GENRE,
	TypeSizeGenre POINTER_SIZE_GENRE>
struct AutotunedGenre <ProblemType, CUDA_ARCH, _PROB_SIZE_GENRE, SM20, TYPE_SIZE_GENRE, POINTER_SIZE_GENRE>
	: Policy<ProblemType, SM20, util::io::ld::NONE, util::io::st::NONE, false, false, false, true, 10,
		8, 7, 1, 2, 5,
		5, 2, 0, 5,
		8, 7, 2, 0, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = _PROB_SIZE_GENRE;
};



//-----------------------------------------------------------------------------
// SM1.3 specializations(s)
//-----------------------------------------------------------------------------


// Temporary
template <
	typename ProblemType,
	int CUDA_ARCH,
	ProbSizeGenre _PROB_SIZE_GENRE,
	TypeSizeGenre TYPE_SIZE_GENRE,
	TypeSizeGenre POINTER_SIZE_GENRE>
struct AutotunedGenre <ProblemType, CUDA_ARCH, _PROB_SIZE_GENRE, SM13, TYPE_SIZE_GENRE, POINTER_SIZE_GENRE>
	: Policy<ProblemType, SM13, util::io::ld::NONE, util::io::st::NONE, false, false, false, false, 10,
		8, 7, 1, 2, 5,
		5, 2, 0, 5,
		8, 7, 2, 0, 5>
{
	static const ProbSizeGenre PROB_SIZE_GENRE = _PROB_SIZE_GENRE;
};



//-----------------------------------------------------------------------------
// SM1.0 specializations(s)
//-----------------------------------------------------------------------------







/******************************************************************************
 * Scan kernel entry points that can derive a tuned granularity type
 * implicitly from the PROB_SIZE_GENRE template parameter.  (As opposed to having
 * the granularity type passed explicitly.)
 *
 * TODO: Section can be removed if CUDA Runtime is fixed to
 * properly support template specialization around kernel call sites.
 ******************************************************************************/

/**
 * Tuned upsweep reduction kernel entry point
 */
template <typename ProblemType, int PROB_SIZE_GENRE>
__launch_bounds__ (
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Upsweep::THREADS),
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Upsweep::CTA_OCCUPANCY))
__global__ void TunedUpsweepKernel(
	typename ProblemType::KeyType				*d_in_keys,
	typename ProblemType::ValueType				*d_in_values,
	typename ProblemType::SpinePartialType		*d_spine_partials,
	typename ProblemType::SpineFlagType			*d_spine_flags,
	util::CtaWorkDistribution<typename ProblemType::SizeT> work_decomposition)
{
	// Load the tuned granularity type identified by the enum for this architecture
	typedef typename AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Upsweep KernelPolicy;

	// Shared storage for the kernel
	__shared__ typename KernelPolicy::SmemStorage smem_storage;

	upsweep::UpsweepPass<KernelPolicy>(
		d_in_keys,
		d_in_values,
		d_spine_partials,
		d_spine_flags,
		work_decomposition,
		smem_storage);
}

/**
 * Tuned spine consecutive reduction kernel entry point
 */
template <typename ProblemType, int PROB_SIZE_GENRE>
__launch_bounds__ (
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Spine::THREADS),
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Spine::CTA_OCCUPANCY))
__global__ void TunedSpineKernel(
	typename ProblemType::SpinePartialType 	*d_in_partials,
	typename ProblemType::SpinePartialType 	*d_out_partials,
	typename ProblemType::SpineFlagType		*d_in_flags,
	typename ProblemType::SpineFlagType		*d_out_flags,
	typename ProblemType::SpineSizeT 		spine_elements)
{
	// Load the tuned granularity type identified by the enum for this architecture
	typedef typename AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Spine KernelPolicy;

	// Shared storage for the kernel
	__shared__ typename KernelPolicy::SmemStorage smem_storage;

	spine::SpinePass<KernelPolicy>(
		d_in_partials,
		d_out_partials,
		d_in_flags,
		d_out_flags,
		spine_elements,
		smem_storage);
}


/**
 * Tuned downsweep consecutive reduction kernel entry point
 */
template <typename ProblemType, int PROB_SIZE_GENRE>
__launch_bounds__ (
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Downsweep::THREADS),
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Downsweep::CTA_OCCUPANCY))
__global__ void TunedDownsweepKernel(
	typename ProblemType::KeyType 								*d_in_keys,
	typename ProblemType::KeyType								*d_out_keys,
	typename ProblemType::ValueType 							*d_in_values,
	typename ProblemType::ValueType 							*d_out_values,
	typename ProblemType::SpinePartialType 						*d_spine_partials,
	typename ProblemType::SpineFlagType 						*d_spine_flags,
	typename ProblemType::SizeT									*d_num_compacted,
	util::CtaWorkDistribution<typename ProblemType::SizeT> 		work_decomposition)
{
	// Load the tuned granularity type identified by the enum for this architecture
	typedef typename AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Downsweep KernelPolicy;

	// Shared storage for the kernel
	__shared__ typename KernelPolicy::SmemStorage smem_storage;

	downsweep::DownsweepPass<KernelPolicy>(
		d_in_keys,
		d_out_keys,
		d_in_values,
		d_out_values,
		d_spine_partials,
		d_spine_flags,
		d_num_compacted,
		work_decomposition,
		smem_storage);
}

/**
 * Tuned single consecutive reduction kernel entry point
 */
template <typename ProblemType, int PROB_SIZE_GENRE>
__launch_bounds__ (
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Single::THREADS),
	(AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Single::CTA_OCCUPANCY))
__global__ void TunedSingleKernel(
	typename ProblemType::KeyType			*d_in_keys,
	typename ProblemType::KeyType			*d_out_keys,
	typename ProblemType::ValueType			*d_in_values,
	typename ProblemType::ValueType			*d_out_values,
	typename ProblemType::SizeT				*d_num_compacted,
	typename ProblemType::SizeT 			num_elements)
{
	// Load the tuned granularity type identified by the enum for this architecture
	typedef typename AutotunedGenre<ProblemType, __B40C_CUDA_ARCH__, (ProbSizeGenre) PROB_SIZE_GENRE>::Single KernelPolicy;

	// Shared storage for the kernel
	__shared__ typename KernelPolicy::SmemStorage smem_storage;

	single::SinglePass<KernelPolicy>(
		d_in_keys,
		d_out_keys,
		d_in_values,
		d_out_values,
		d_num_compacted,
		num_elements,
		smem_storage);
}


/******************************************************************************
 * Autotuned policy
 *******************************************************************************/

/**
 * Autotuned policy type
 */
template <
	typename ProblemType,
	int CUDA_ARCH,
	ProbSizeGenre PROB_SIZE_GENRE>
struct AutotunedPolicy :
	AutotunedGenre<
		ProblemType,
		CUDA_ARCH,
		PROB_SIZE_GENRE>
{
	//---------------------------------------------------------------------
	// Typedefs
	//---------------------------------------------------------------------

	typedef typename ProblemType::KeyType 			KeyType;
	typedef typename ProblemType::ValueType			ValueType;
	typedef typename ProblemType::SizeT 			SizeT;

	typedef typename ProblemType::SpinePartialType 	SpinePartialType;
	typedef typename ProblemType::SpineFlagType 	SpineFlagType;
	typedef typename ProblemType::SpineSizeT 		SpineSizeT;

	typedef void (*UpsweepKernelPtr)(KeyType*, ValueType*, SpinePartialType*, SpineFlagType*, util::CtaWorkDistribution<SizeT>);
	typedef void (*SpineKernelPtr)(SpinePartialType*, SpinePartialType*, SpineFlagType*, SpineFlagType*, SpineSizeT);
	typedef void (*DownsweepKernelPtr)(KeyType*, KeyType*, ValueType*, ValueType*, SpinePartialType*,  SizeT*, SpineFlagType*, util::CtaWorkDistribution<SizeT>);
	typedef void (*SingleKernelPtr)(KeyType*, KeyType*, ValueType*, ValueType*, SizeT*, SizeT);

	//---------------------------------------------------------------------
	// Kernel function pointer retrieval
	//---------------------------------------------------------------------

	static UpsweepKernelPtr UpsweepKernel() {
		return TunedUpsweepKernel<ProblemType, PROB_SIZE_GENRE>;
	}

	static SpineKernelPtr SpineKernel() {
		return TunedSpineKernel<ProblemType, PROB_SIZE_GENRE>;
	}

	static DownsweepKernelPtr DownsweepKernel() {
		return TunedDownsweepKernel<ProblemType, PROB_SIZE_GENRE>;
	}

	static SingleKernelPtr SingleKernel() {
		return TunedSingleKernel<ProblemType, PROB_SIZE_GENRE>;
	}
};




}// namespace consecutive_reduction
}// namespace b40c
