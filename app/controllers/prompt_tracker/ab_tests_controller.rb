# frozen_string_literal: true

module PromptTracker
  # Controller for managing A/B tests
  class AbTestsController < ApplicationController
    before_action :set_ab_test, only: [ :show, :edit, :update, :destroy, :start, :pause, :resume, :complete, :cancel, :analyze ]
    before_action :set_prompt, only: [ :new, :create ]

    # GET /ab_tests
    # List all A/B tests with filtering
    def index
      @ab_tests = AbTest.includes(:prompt).order(created_at: :desc)

      # Filter by status
      if params[:status].present?
        @ab_tests = @ab_tests.where(status: params[:status])
      end

      # Filter by prompt
      if params[:prompt_id].present?
        @ab_tests = @ab_tests.where(prompt_id: params[:prompt_id])
      end

      # Search by name
      if params[:q].present?
        query = "%#{params[:q]}%"
        @ab_tests = @ab_tests.where("name LIKE ?", query)
      end

      # Pagination
      @ab_tests = @ab_tests.page(params[:page]).per(20)

      # Get prompts for filter dropdown
      @prompts = Prompt.order(:name)
    end

    # GET /ab_tests/:id
    # Show A/B test details with analysis
    def show
      @variants = @ab_test.variants
      @variant_stats = calculate_variant_stats
      @analysis = analyze_test if @ab_test.running?
    end

    # GET /ab_tests/new
    # New A/B test form
    def new
      @ab_test = @prompt.ab_tests.build(
        traffic_split: { "A" => 50, "B" => 50 },
        confidence_level: 0.95,
        minimum_sample_size: 100
      )
      @available_versions = @prompt.prompt_versions.where(status: [ "active", "draft" ]).order(version_number: :desc)
    end

    # POST /ab_tests
    # Create new A/B test
    def create
      @ab_test = @prompt.ab_tests.build(ab_test_params)
      normalize_traffic_split(@ab_test)

      if @ab_test.save
        redirect_to ab_test_path(@ab_test), notice: "A/B test created successfully."
      else
        @available_versions = @prompt.prompt_versions.where(status: [ "active", "draft" ]).order(version_number: :desc)
        render :new, status: :unprocessable_entity
      end
    end

    # GET /ab_tests/:id/edit
    # Edit A/B test (only if draft)
    def edit
      unless @ab_test.draft?
        redirect_to ab_test_path(@ab_test), alert: "Cannot edit a running or completed test."
        return
      end

      @available_versions = @ab_test.prompt.prompt_versions.where(status: [ "active", "draft" ]).order(version_number: :desc)
    end

    # PATCH /ab_tests/:id
    # Update A/B test (only if draft)
    def update
      unless @ab_test.draft?
        redirect_to ab_test_path(@ab_test), alert: "Cannot update a running or completed test."
        return
      end

      @ab_test.assign_attributes(ab_test_params)
      normalize_traffic_split(@ab_test)

      if @ab_test.save
        redirect_to ab_test_path(@ab_test), notice: "A/B test updated successfully."
      else
        @available_versions = @ab_test.prompt.prompt_versions.where(status: [ "active", "draft" ]).order(version_number: :desc)
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /ab_tests/:id
    # Delete A/B test (only if draft)
    def destroy
      unless @ab_test.draft?
        redirect_to ab_tests_path, alert: "Cannot delete a running or completed test."
        return
      end

      @ab_test.destroy
      redirect_to ab_tests_path, notice: "A/B test deleted successfully."
    end

    # POST /ab_tests/:id/start
    # Start the A/B test
    def start
      unless @ab_test.draft?
        redirect_to ab_test_path(@ab_test), alert: "Test is already running or completed."
        return
      end

      @ab_test.start!
      redirect_to ab_test_path(@ab_test), notice: "A/B test started successfully."
    end

    # POST /ab_tests/:id/pause
    # Pause the A/B test
    def pause
      unless @ab_test.running?
        redirect_to ab_test_path(@ab_test), alert: "Test is not running."
        return
      end

      @ab_test.pause!
      redirect_to ab_test_path(@ab_test), notice: "A/B test paused successfully."
    end

    # POST /ab_tests/:id/resume
    # Resume a paused A/B test
    def resume
      unless @ab_test.paused?
        redirect_to ab_test_path(@ab_test), alert: "Test is not paused."
        return
      end

      @ab_test.resume!
      redirect_to ab_test_path(@ab_test), notice: "A/B test resumed successfully."
    end

    # POST /ab_tests/:id/complete
    # Complete the A/B test with a winner
    def complete
      unless @ab_test.running?
        redirect_to ab_test_path(@ab_test), alert: "Test is not running."
        return
      end

      winner = params[:winner]
      unless winner.present? && @ab_test.variant_names.include?(winner)
        redirect_to ab_test_path(@ab_test), alert: "Invalid winner variant."
        return
      end

      @ab_test.complete!(winner: winner)

      # Optionally promote winner
      if params[:promote_winner] == "true"
        @ab_test.promote_winner!
        redirect_to ab_test_path(@ab_test), notice: "A/B test completed and winner promoted successfully."
      else
        redirect_to ab_test_path(@ab_test), notice: "A/B test completed successfully."
      end
    end

    # POST /ab_tests/:id/cancel
    # Cancel the A/B test
    def cancel
      if @ab_test.completed?
        redirect_to ab_test_path(@ab_test), alert: "Cannot cancel a completed test."
        return
      end

      @ab_test.cancel!
      redirect_to ab_test_path(@ab_test), notice: "A/B test cancelled successfully."
    end

    # GET /ab_tests/:id/analyze
    # Analyze test results (AJAX endpoint)
    def analyze
      analyzer = AbTestAnalyzer.new(@ab_test)
      @analysis = analyzer.analyze

      respond_to do |format|
        format.json { render json: @analysis }
        format.html { redirect_to ab_test_path(@ab_test) }
      end
    end

    private

    def set_ab_test
      @ab_test = AbTest.includes(:prompt).find(params[:id])
    end

    def set_prompt
      @prompt = Prompt.find(params[:prompt_id])
    end

    def ab_test_params
      params.require(:ab_test).permit(
        :name,
        :description,
        :metric_to_optimize,
        :optimization_direction,
        :confidence_level,
        :minimum_sample_size,
        traffic_split: {},
        variants: [ :name, :version_id ]
      )
    end

    # Normalize traffic_split hash values to integers
    # This is needed because form params come as strings
    def normalize_traffic_split(ab_test)
      return unless ab_test.traffic_split.is_a?(Hash)

      ab_test.traffic_split = ab_test.traffic_split.transform_values do |value|
        value.is_a?(String) ? value.to_i : value
      end
    end

    # Calculate statistics for each variant
    def calculate_variant_stats
      stats = {}

      @ab_test.variant_names.each do |variant_name|
        responses = @ab_test.llm_responses.where(ab_variant: variant_name)
        stats[variant_name] = {
          count: responses.count,
          success_rate: calculate_success_rate(responses),
          avg_response_time: responses.average(:response_time_ms)&.round(2),
          avg_cost: responses.average(:cost_usd)&.round(6),
          avg_tokens: responses.average(:tokens_total)&.round(0)
        }
      end

      stats
    end

    # Calculate success rate for responses
    def calculate_success_rate(responses)
      return 0.0 if responses.empty?
      success_count = responses.where(status: "success").count
      (success_count.to_f / responses.count * 100).round(2)
    end

    # Analyze test using AbTestAnalyzer
    def analyze_test
      analyzer = AbTestAnalyzer.new(@ab_test)
      analyzer.analyze if analyzer.ready_for_analysis?
    end
  end
end
