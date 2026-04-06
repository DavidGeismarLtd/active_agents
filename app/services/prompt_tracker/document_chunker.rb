# frozen_string_literal: true

module PromptTracker
  # Splits uploaded files into overlapping text chunks ready for embedding.
  #
  # Chunking strategy: word-based sliding window with overlap so that
  # context at chunk boundaries is not lost during retrieval.
  #
  # Supported formats: .txt, .md (plain text), .pdf (via pdf-reader gem),
  # .docx (via rubyzip, already a dependency).
  # All other extensions are read as plain text.
  #
  # @example Chunk an uploaded file
  #   chunks = DocumentChunker.chunk(uploaded_file)
  #   # => [{ text: "...", metadata: { filename: "doc.pdf", chunk_index: 0 } }, ...]
  #
  class DocumentChunker
    CHUNK_SIZE    = 500  # approximate tokens via word count
    CHUNK_OVERLAP = 50

    # Split an uploaded file into text chunks.
    #
    # @param file [ActionDispatch::Http::UploadedFile, #read, #original_filename] the uploaded file
    # @return [Array<Hash>] array of chunks, each with :text and :metadata
    def self.chunk(file)
      text   = extract_text(file)
      words  = text.split
      chunks = []
      i      = 0

      while i < words.length
        chunk_words = words[i, CHUNK_SIZE]
        chunks << {
          text:     chunk_words.join(" "),
          metadata: { filename: file.original_filename, chunk_index: chunks.size }
        }
        i += (CHUNK_SIZE - CHUNK_OVERLAP)
      end

      chunks
    end

    private

    SUPPORTED_TEXT_EXTENSIONS = %w[.txt .md .html .json .csv].freeze

    def self.extract_text(file)
      ext = File.extname(file.original_filename.to_s).downcase
      case ext
      when *SUPPORTED_TEXT_EXTENSIONS
        file.read.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
      when ".pdf"
        extract_pdf_text(file)
      when ".docx"
        extract_docx_text(file)
      else
        raise "Unsupported file type: #{ext}. Supported: #{(SUPPORTED_TEXT_EXTENSIONS + %w[.pdf .docx]).join(', ')}"
      end
    end

    def self.extract_pdf_text(file)
      require "pdf-reader"

      reader = PDF::Reader.new(file.tempfile)
      reader.pages.map(&:text).join("\n")
    rescue LoadError
      raise "pdf-reader gem is required for PDF support. Add `gem 'pdf-reader'` to your Gemfile."
    rescue StandardError => e
      Rails.logger.error("[DocumentChunker] PDF extraction failed: #{e.message}")
      ""
    end

    # Extract text from .docx files using rubyzip (already a gem dependency).
    # .docx is a ZIP containing XML; the body text lives in word/document.xml.
    def self.extract_docx_text(file)
      require "zip"

      text_parts = []
      Zip::File.open(file.tempfile.path) do |zip|
        entry = zip.find_entry("word/document.xml")
        raise "Invalid .docx — word/document.xml not found" unless entry

        xml = entry.get_input_stream.read
        # Strip XML tags to get plain text. Handles <w:t> and <w:p> (paragraph breaks).
        # Replace paragraph/break tags with newlines, then strip all remaining tags.
        text = xml.gsub(%r{</w:p>}, "\n")
        text = text.gsub(/<[^>]+>/, "")
        text = text.encode("UTF-8", invalid: :replace, undef: :replace)
        text_parts << text
      end
      text_parts.join("\n")
    rescue StandardError => e
      Rails.logger.error("[DocumentChunker] DOCX extraction failed: #{e.message}")
      ""
    end
  end
end
