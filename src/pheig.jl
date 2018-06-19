#= src/pheig.jl
=#

mutable struct PartialHermitianEigen{T,Tr<:Real} <: Factorization{T}
  values::Vector{Tr}
  vectors::Matrix{T}
end
const PartialHermEigen = PartialHermitianEigen

conj!(A::PartialHermEigen) = PartialHermEigen(conj!(A.values), conj!(A.vectors))
conj(A::PartialHermEigen) = conj!(copy(A))

function convert(::Type{PartialHermEigen{T}}, A::PartialHermEigen) where T
  Tr = real(T)
  PartialHermEigen(convert(Array{Tr}, A.values), convert(Array{T}, A.vectors))
end
convert(::Type{Factorization{T}}, A::PartialHermEigen{T,<:Real}) where {T} =
  A
convert(::Type{Factorization{T}}, A::PartialHermEigen) where {T} =
  convert(PartialHermEigen{T}, A)
convert(::Type{Array}, A::PartialHermEigen) = full(A)
convert(::Type{Array{T}}, A::PartialHermEigen) where {T} = convert(Array{T}, full(A))

copy(A::PartialHermEigen) = PartialHermEigen(copy(A.values), copy(A.vectors))

adjoint!(A::PartialHermEigen) = A
adjoint(A::PartialHermEigen) = copy(A)
transpose!(A::PartialHermEigen) = conj!(A.vectors)
transpose(A::PartialHermEigen) = PartialHermEigen(A.values, conj(A.vectors))

full(A::PartialHermEigen) = (A[:vectors]*Diagonal(A[:values]))*A[:vectors]'

function getindex(A::PartialHermEigen, d::Symbol)
  if     d == :k        return length(A.values)
  elseif d == :values   return A.values
  elseif d == :vectors  return A.vectors
  else                  throw(KeyError(d))
  end
end

ishermitian(::PartialHermEigen) = true
issymmetric(A::PartialHermEigen{T}) where {T} = isreal(A)

isreal(::PartialHermEigen{T}) where {T} = T <: Real

ndims(::PartialHermEigen) = 2

size(A::PartialHermEigen) = (size(A.vectors,1), size(A.vectors,1))
size(A::PartialHermEigen, dim::Integer) =
  dim == 1 || dim == 2 ? size(A.vectors,1) : 1

# BLAS/LAPACK multiplication/division routines

## left-multiplication

mul!(
 y::StridedVector{T}, A::PartialHermEigen{T}, x::StridedVector{T}) where {T} =
  mul!(y, A[:vectors], scalevec!(A[:values], A[:vectors]'*x))
mul!(
 C::StridedMatrix{T}, A::PartialHermEigen{T}, B::StridedMatrix{T}) where {T} =
  mul!(C, A[:vectors], scale!(A[:values], A[:vectors]'*B))

A_mul_Bc!(C::StridedMatrix{T}, A::PartialHermEigen{T}, B::StridedMatrix{T}) where {T} =
  mul!(C, A[:vectors], scale!(A[:values], A[:vectors]'*B'))
A_mul_Bt!(
C::StridedMatrix{T}, A::PartialHermEigen{T}, B::StridedMatrix{T}) where {T<:Real} =
  A_mul_Bc!(C, A, B)
A_mul_Bt!!(
C::StridedMatrix{T}, A::PartialHermEigen{T}, B::StridedMatrix{T}) where {T<:Complex} =
  A_mul_Bc!(C, A, conj!(B))  # overwrites B
function A_mul_Bt!(
    C::StridedMatrix{T}, A::PartialHermEigen{T}, B::StridedMatrix{T}) where T<:Complex
  size(B, 1) <= A[:k] && return A_mul_Bt!!(C, A, copy(B))
  tmp = (A[:vectors]')*transpose(B)
  scale!(A[:values], tmp)
  mul!(C, A[:vectors], tmp)
end

Ac_mul_B!(
 C::StridedVecOrMat{T}, A::PartialHermEigen{T}, B::StridedVecOrMat{T}) where {T} =
  mul!(C, A, B)
function At_mul_B!(
    y::StridedVector{T}, A::PartialHermEigen{T}, x::StridedVector{T}) where T
  tmp = transpose(A[:vectors])*x
  scalevec!(A[:values], tmp)
  mul!(y, A[:vectors], conj!(tmp))
  conj!(y)
end
function At_mul_B!(
    C::StridedMatrix{T}, A::PartialHermEigen{T}, B::StridedMatrix{T}) where T
  tmp = transpose(A[:vectors])*B
  scale!(A[:values], tmp)
  mul!(C, A[:vectors], conj!(tmp))
  conj!(C)
end

Ac_mul_Bc!(
 C::StridedMatrix{T}, A::PartialHermEigen{T}, B::StridedMatrix{T}) where {T} =
  A_mul_Bc!(C, A, B)
function At_mul_Bt!(
    C::StridedMatrix{T}, A::PartialHermEigen{T}, B::StridedMatrix{T}) where T
  tmp = transpose(A[:vectors])*transpose(B)
  scale!(A[:values], tmp)
  mul!(C, A[:vectors], conj!(tmp))
  conj!(C)
end

## right-multiplication

mul!(C::StridedMatrix{T}, A::StridedMatrix{T}, B::PartialHermEigen{T}) where {T} =
  A_mul_Bc!(C, scale!(A*B[:vectors], B[:values]), B[:vectors])

A_mul_Bc!(C::StridedMatrix{T}, A::StridedMatrix{T}, B::PartialHermEigen{T}) where {T} =
  mul!(C, A, B)
function A_mul_Bt!!(
    C::StridedMatrix{T}, A::StridedMatrix{T}, B::PartialHermEigen{T}) where T
  tmp = conj!(A)*B[:vectors]
  scale!(conj!(tmp), B[:values])
  A_mul_Bt!(C, tmp, B[:vectors])
end  # overwrites A
function A_mul_Bt!(
    C::StridedMatrix{T}, A::StridedMatrix{T}, B::PartialHermEigen{T}) where T
  size(A, 1) <= B[:k] && return A_mul_Bt!!(C, copy(A), B)
  tmp = A*conj(B[:vectors])
  scale!(tmp, B[:values])
  A_mul_Bt!(C, tmp, B[:vectors])
end

for f in (:Ac_mul_B, :At_mul_B)
  f! = Symbol(f, "!")
  @eval begin
    function $f!(
        C::StridedMatrix{T}, A::StridedMatrix{T}, B::PartialHermEigen{T}) where T
      tmp = $f(A, B[:vectors])
      scale!(tmp, B[:values])
      A_mul_Bc!(C, tmp, B[:vectors])
    end
  end
end

Ac_mul_Bc!(
 C::StridedMatrix{T}, A::StridedMatrix{T}, B::PartialHermEigen{T}) where {T} =
  Ac_mul_B!(C, A, B)
function At_mul_Bt!(
    C::StridedMatrix{T}, A::StridedMatrix{T}, B::PartialHermEigen{T}) where T
  tmp = A'*B[:vectors]
  scale!(conj!(tmp), B[:values])
  A_mul_Bt!(C, tmp, B[:vectors])
end

## left-division (pseudoinverse left-multiplication)
A_ldiv_B!(
 y::StridedVector{T}, A::PartialHermEigen{T}, x::StridedVector{T}) where {T} =
  mul!(y, A[:vectors], iscalevec!(A[:values], A[:vectors]'*x))
A_ldiv_B!(
 C::StridedMatrix{T}, A::PartialHermEigen{T}, B::StridedMatrix{T}) where {T} =
  mul!(C, A[:vectors], iscale!(A[:values], A[:vectors]'*B))

# standard operations

## left-multiplication

for (f, f!, i) in ((:*,        :mul!,  1),
                   (:Ac_mul_B, :Ac_mul_B!, 2),
                   (:At_mul_B, :At_mul_B!, 2))
  @eval begin
    function $f(A::PartialHermEigen{TA}, B::StridedVector{TB}) where {TA,TB}
      T = promote_type(TA, TB)
      AT = convert(PartialHermEigen{T}, A)
      BT = (T == TB ? B : convert(Array{T}, B))
      CT = Array{T}(undef, size(A,$i))
      $f!(CT, AT, BT)
    end
  end
end

for (f, f!, i, j) in ((:*,         :mul!,   1, 2),
                      (:A_mul_Bc,  :A_mul_Bc!,  1, 1),
                      (:A_mul_Bt,  :A_mul_Bt!,  1, 1),
                      (:Ac_mul_B,  :Ac_mul_B!,  2, 2),
                      (:Ac_mul_Bc, :Ac_mul_Bc!, 2, 1),
                      (:At_mul_B,  :At_mul_B!,  2, 2),
                      (:At_mul_Bt, :At_mul_Bt!, 2, 1))
  @eval begin
    function $f(A::PartialHermEigen{TA}, B::StridedMatrix{TB}) where {TA,TB}
      T = promote_type(TA, TB)
      AT = convert(PartialHermEigen{T}, A)
      BT = (T == TB ? B : convert(Array{T}, B))
      CT = Array{T}(undef, size(A,$i), size(B,$j))
      $f!(CT, AT, BT)
    end
  end
end

## right-multiplication
for (f, f!, i, j) in ((:*,         :mul!,   1, 2),
                      (:A_mul_Bc,  :A_mul_Bc!,  1, 1),
                      (:A_mul_Bt,  :A_mul_Bt!,  1, 1),
                      (:Ac_mul_B,  :Ac_mul_B!,  2, 2),
                      (:Ac_mul_Bc, :Ac_mul_Bc!, 2, 1),
                      (:At_mul_B,  :At_mul_B!,  2, 2),
                      (:At_mul_Bt, :At_mul_Bt!, 2, 1))
  @eval begin
    function $f(A::StridedMatrix{TA}, B::PartialHermEigen{TB}) where {TA,TB}
      T = promote_type(TA, TB)
      AT = (T == TA ? A : convert(Array{T}, A))
      BT = convert(PartialHermEigen{T}, B)
      CT = Array{T}(undef, size(A,$i), size(B,$j))
      $f!(CT, AT, BT)
    end
  end
end

## left-division
function \(A::PartialHermEigen{TA}, B::StridedVector{TB}) where {TA,TB}
  T = promote_type(TA, TB)
  AT = convert(PartialHermEigen{T}, A)
  BT = (T == TB ? B : convert(Array{T}, B))
  CT = Array{T}(undef, size(A,2))
  A_ldiv_B!(CT, AT, BT)
end
function \(A::PartialHermEigen{TA}, B::StridedMatrix{TB}) where {TA,TB}
  T = promote_type(TA, TB)
  AT = convert(PartialHermEigen{T}, A)
  BT = (T == TB ? B : convert(Array{T}, B))
  CT = Array{T}(undef, size(A,2), size(B,2))
  A_ldiv_B!(CT, AT, BT)
end

# factorization routines

function pheigfact(
    A::AbstractMatOrLinOp{T}, opts::LRAOptions=LRAOptions(T); args...) where T
  checksquare(A)
  !ishermitian(A) && error("matrix must be Hermitian")
  opts = isempty(args) ? opts : copy(opts; args...)
  V = idfact(:n, A, opts)
  F = qrfact!(full(:c, V))
  Q = F[:Q]
  B = F[:R]*(A[V[:sk],V[:sk]]*F[:R]')
  F = eigfact!(hermitianize!(B))
  F = PartialHermEigen(F.values, F.vectors)
  kn, kp = pheigrank(F[:values], opts)
  n = size(B, 2)
  if kn + kp < n
    idx = [1:kn; n-kp+1:n]
    F.values  = F.values[idx]
    F.vectors = F.vectors[:,idx]
  end
  pheigorth!(F.values, F.vectors, opts)
  F.vectors = Q*F.vectors
  F
end

function pheigvals(
    A::AbstractMatOrLinOp{T}, opts::LRAOptions=LRAOptions(T); args...) where T
  checksquare(A)
  !ishermitian(A) && error("matrix must be Hermitian")
  opts = isempty(args) ? opts : copy(opts; args...)
  V = idfact(:n, A, opts)
  F = qrfact!(full(:c, V))
  B = F[:R]*(A[V[:sk],V[:sk]]*F[:R]')
  v = eigvals!(hermitianize!(B))
  kn, kp = pheigrank(v, opts)
  n = size(B, 2)
  kn + kp < n && return v[[1:kn; n-kp+1:n]]
  v
end

for f in (:pheigfact, :pheigvals)
  @eval $f(A, args...; kwargs...) = $f(LinOp(A), args...; kwargs...)
end

function pheig(A, args...; kwargs...)
  F = pheigfact(A, args...; kwargs...)
  F.values, F.vectors
end

function pheigrank(w::Vector{T}, opts::LRAOptions) where T<:Real
  n = length(w)
  k = opts.rank >= 0 ? min(opts.rank, n) : n
  wmax = max(abs(w[1]), abs(w[n]))
  idx = searchsorted(w, 0)
  kn = pheigrank1(view(w,1:first(idx)-1),   opts, wmax)
  kp = pheigrank1(view(w,n:-1:last(idx)+1), opts, wmax)
  kn, kp
end
function pheigrank1(w::StridedVector, opts::LRAOptions, wmax::T) where T<:Real
  k = length(w)
  k = opts.rank >= 0 ? min(opts.rank, k) : k
  ptol = max(opts.atol, opts.rtol*wmax)
  @inbounds for i = 2:k
    abs(w[i]) <= ptol && return i - 1
  end
  k
end

## reorthonormalize eigenvalue cluster (issue in LAPACK)
function pheigorth!(
    values::Vector{T}, vectors::Matrix, opts::LRAOptions) where T<:Real
  n = length(values)
  a = 1
  @inbounds while a <= n
    va = values[a]
    b  = a + 1
    while b <= n
      vb = values[b]
      symrelerr(va, vb) > opts.pheig_orthtol && break
      b += 1
    end
    b -= 1
    for i = a:b
      vi = view(vectors, :, i)
      for j = i+1:b
        vj = view(vectors, :, j)
        BLAS.axpy!(-dot(vi,vj), vi, vj)
      end
    end
    a = b + 1
  end
end
