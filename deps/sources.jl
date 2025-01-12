# MIT License

# Copyright (c) Microsoft Corporation.

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE

import HTTP
import SHA
import ZipFile

const Maybe{T} = Union{T, Nothing}

"""
Verify a list of `sources` located in `source_dir`. If AGF files are missing or invalid, try to download them using the
information provided in `sources`.

Each `source ∈ sources` is a collection of strings in the format `name, sha256sum, url [, POST_data]`, where the last
optional string is used to specify data to be sent in a POST request. This allows us to download a greater range of
sources (e.g. Sumita).

Modifies `sources` in-place such that only verified sources remain.
"""
function verify_sources!(sources::AbstractVector{<:AbstractVector{<:AbstractString}}, source_dir::AbstractString)
    # track missing sources as we go and delete them afterwards to avoid modifying our iterator
    missing_sources = []

    for (i, source) in enumerate(sources)
        name, sha256sum = source[1:2]
        source_file = joinpath(source_dir, "$(name).agf")
        verified = verify_source(source_file, sha256sum)
        if !verified && length(source) >= 3
            # try downloading and re-verifying the source if download information is provided (sources[3:end])
            download_source(source_file, source[3:end]...)
            verified = verify_source(source_file, sha256sum)
        end
        if !verified
            push!(missing_sources, i)
        end
    end

    deleteat!(sources, missing_sources)
end

"""
Verify a source file using SHA256, returning true if successful. Otherwise, remove the file and return false.
"""
function verify_source(source_file::AbstractString, sha256sum::AbstractString)
    if !isfile(source_file)
        @info "[-] Missing file at $source_file"
    elseif sha256sum == SHA.bytes2hex(SHA.sha256(read(source_file)))
        @info "[✓] Verified file at $source_file"
        return true
    else
        @info "[x] Removing unverified file at $source_file"
        rm(source_file)
    end
    return false
end

"""
Download and unzip an AGF glass catalog from a publicly available source. Supports POST requests.
"""
function download_source(sourcefile::AbstractString, url::AbstractString, POST_data::Maybe{AbstractString} = nothing)
    @info "Downloading source file from $url"
    try
        headers = ["Content-Type" => "application/x-www-form-urlencoded"]
        resp = isnothing(POST_data) ? HTTP.get(url) : HTTP.post(url, headers, POST_data)
        reader = ZipFile.Reader(IOBuffer(resp.body))
        write(sourcefile, read(reader.files[end]))  # todo detect .agf file(s)
    catch e
        @error e
    end
end
