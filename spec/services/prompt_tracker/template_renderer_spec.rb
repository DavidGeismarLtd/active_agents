# frozen_string_literal: true

require "rails_helper"

module PromptTracker
  RSpec.describe TemplateRenderer do
    describe "#render" do
      context "with Mustache-style templates" do
        it "renders simple variable substitution" do
          renderer = TemplateRenderer.new("Hello {{name}}!")
          result = renderer.render({ name: "John" })

          expect(result).to eq("Hello John!")
        end

        it "renders multiple variables" do
          renderer = TemplateRenderer.new("{{greeting}} {{name}}, welcome to {{place}}!")
          result = renderer.render({ greeting: "Hi", name: "Alice", place: "Wonderland" })

          expect(result).to eq("Hi Alice, welcome to Wonderland!")
        end

        it "converts values to strings" do
          renderer = TemplateRenderer.new("Count: {{count}}")
          result = renderer.render({ count: 42 })

          expect(result).to eq("Count: 42")
        end

        it "works with indifferent access" do
          renderer = TemplateRenderer.new("Hello {{name}}!")
          result = renderer.render({ "name" => "Bob" })

          expect(result).to eq("Hello Bob!")
        end
      end

      context "with Liquid templates" do
        it "renders simple Liquid variables" do
          renderer = TemplateRenderer.new("Hello {{ name }}!")
          result = renderer.render({ name: "John" }, engine: :liquid)

          expect(result).to eq("Hello John!")
        end

        it "renders Liquid filters" do
          renderer = TemplateRenderer.new("Hello {{ name | upcase }}!")
          result = renderer.render({ name: "john" })

          expect(result).to eq("Hello JOHN!")
        end

        it "renders Liquid conditionals" do
          template = "{% if premium %}Premium user{% else %}Basic user{% endif %}"
          renderer = TemplateRenderer.new(template)

          expect(renderer.render({ premium: true })).to eq("Premium user")
          expect(renderer.render({ premium: false })).to eq("Basic user")
        end

        it "renders Liquid loops" do
          template = "{% for item in items %}{{ item }} {% endfor %}"
          renderer = TemplateRenderer.new(template)
          result = renderer.render({ items: %w[a b c] })

          expect(result).to eq("a b c ")
        end

        it "renders nested object access" do
          renderer = TemplateRenderer.new("Hello {{ user.name }}!")
          result = renderer.render({ user: { "name" => "Alice" } })

          expect(result).to eq("Hello Alice!")
        end

        it "combines filters and conditionals" do
          template = "{% if name %}Hello {{ name | capitalize }}!{% endif %}"
          renderer = TemplateRenderer.new(template)

          expect(renderer.render({ name: "john" })).to eq("Hello John!")
          expect(renderer.render({ name: nil })).to eq("")
        end
      end

      context "with explicit engine selection" do
        it "forces Liquid engine" do
          renderer = TemplateRenderer.new("Hello {{ name | upcase }}!")
          result = renderer.render({ name: "john" }, engine: :liquid)

          expect(result).to eq("Hello JOHN!")
        end

        it "forces Mustache engine" do
          renderer = TemplateRenderer.new("Hello {{name}}!")
          result = renderer.render({ name: "John" }, engine: :mustache)

          expect(result).to eq("Hello John!")
        end

        it "raises error for unknown engine" do
          renderer = TemplateRenderer.new("Hello {{name}}!")

          expect {
            renderer.render({ name: "John" }, engine: :unknown)
          }.to raise_error(ArgumentError, /Unknown template engine/)
        end
      end

      context "with auto-detection" do
        it "uses Liquid for templates with filters" do
          renderer = TemplateRenderer.new("{{ name | upcase }}")
          result = renderer.render({ name: "test" })

          expect(result).to eq("TEST")
        end

        it "uses Liquid for templates with tags" do
          renderer = TemplateRenderer.new("{% if true %}yes{% endif %}")
          result = renderer.render({})

          expect(result).to eq("yes")
        end

        it "uses Mustache for simple templates" do
          renderer = TemplateRenderer.new("{{name}}")
          result = renderer.render({ name: "test" })

          expect(result).to eq("test")
        end
      end
    end

    describe "#valid?" do
      it "returns true for valid Liquid templates" do
        renderer = TemplateRenderer.new("Hello {{ name }}!")

        expect(renderer).to be_valid
      end

      it "returns false for invalid Liquid templates" do
        renderer = TemplateRenderer.new("{% if %}")

        expect(renderer).not_to be_valid
        expect(renderer.errors).not_to be_empty
      end

      it "returns true for Mustache templates" do
        renderer = TemplateRenderer.new("Hello {{name}}!")

        expect(renderer).to be_valid
      end
    end

    describe "#liquid_template?" do
      it "detects Liquid filters" do
        renderer = TemplateRenderer.new("{{ name | upcase }}")

        expect(renderer).to be_liquid_template
      end

      it "detects Liquid tags" do
        renderer = TemplateRenderer.new("{% if condition %}yes{% endif %}")

        expect(renderer).to be_liquid_template
      end

      it "detects Liquid object notation" do
        renderer = TemplateRenderer.new("{{ user.name }}")

        expect(renderer).to be_liquid_template
      end

      it "returns false for Mustache templates" do
        renderer = TemplateRenderer.new("{{name}}")

        expect(renderer).not_to be_liquid_template
      end
    end
  end
end
