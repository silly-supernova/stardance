class Admin::ProjectsController < Admin::ApplicationController
  def index
    authorize ::Project
    @query = params[:query]
    @filter = params[:filter] || "active"

    projects = case @filter
    when "deleted"
      ::Project.unscoped.deleted
    when "all"
      ::Project.unscoped.all
    else
      ::Project.all
    end

    if @query.present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      projects = projects.where("title ILIKE ? OR description ILIKE ?", q, q)
    end

    @pagy, @projects = pagy(:offset, projects.order(:id))
  end

  def show
    @project = ::Project.unscoped.find(params[:id])
    authorize @project
  end

  def votes
    @project = ::Project.find(params[:id])
    authorize @project, :show?

    @pagy, @votes = pagy(
      @project.votes.includes(:user, :events).order(created_at: :desc)
    )
  end

  def restore
    @project = ::Project.unscoped.find(params[:id])
    authorize @project

    if @project.deleted?
      @project.restore!
      redirect_to admin_project_path(@project), notice: "Project restored successfully."
    else
      redirect_to admin_project_path(@project), alert: "Project is not deleted."
    end
  end

  def delete
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :destroy?

    if @project.deleted?
      redirect_to admin_project_path(@project), alert: "Project is already deleted."
    else
      @project.soft_delete!(force: true)
      redirect_to admin_project_path(@project), notice: "Project deleted successfully."
    end
  end

  def update_ship_status
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :update?

    old_status = @project.ship_status
    new_status = params[:ship_status]

    unless ::Project.aasm.states.map { |s| s.name.to_s }.include?(new_status)
      redirect_to admin_project_path(@project), alert: "Invalid ship status."
      return
    end

    if old_status == new_status
      redirect_to admin_project_path(@project), alert: "Project is already #{new_status}."
      return
    end

    @project.update_column(:ship_status, new_status)
    sync_last_ship_event_certification(new_status)

    log_admin_version("update", ship_status: [ old_status, new_status ])

    redirect_to admin_project_path(@project), notice: "Ship status changed from #{old_status} to #{new_status}."
  end

  def update_hardware_stage
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :update?

    old_stage = @project.hardware_stage
    new_stage = params[:hardware_stage].presence
    reason = params[:reason].to_s.strip

    unless ([ nil ] + ::Project::HARDWARE_STAGES).include?(new_stage)
      redirect_to admin_project_path(@project), alert: "Invalid project kind."
      return
    end

    if reason.blank?
      redirect_to admin_project_path(@project), alert: "Explain why the project kind is being changed."
      return
    end

    if old_stage == new_stage
      redirect_to admin_project_path(@project), alert: "Project kind is already #{hardware_stage_label(new_stage)}."
      return
    end

    funding_lock_bypassed = @project.has_any_funding_request?
    # Setting Software overrules the AI classifier. Without this, a stale
    # project_type == "Hardware" would keep the project out of the review queue
    # (Certification::Ship.excluding_hardware) even after the override.
    old_project_type = @project.project_type
    clear_classifier = new_stage.nil? && old_project_type == "Hardware"

    @project.hardware_stage = new_stage
    @project.project_type = nil if clear_classifier
    ::PaperTrail.request(enabled: false) do
      @project.save!(validate: false)
    end

    changes = {
      "hardware_stage" => [ old_stage, new_stage ],
      "project_kind" => [ hardware_stage_label(old_stage), hardware_stage_label(new_stage) ],
      "reason" => reason,
      "funding_lock_bypassed" => funding_lock_bypassed
    }
    changes["project_type"] = [ old_project_type, nil ] if clear_classifier
    log_admin_version("admin_hardware_stage_update", changes)

    redirect_to admin_project_path(@project),
                notice: "Project kind changed from #{hardware_stage_label(old_stage)} to #{hardware_stage_label(new_stage)}."
  end

  # Wipes the project's most recent ship: destroys the ship event (and, via
  # dependent associations, its post, ledger entries, vote assignments and
  # mission submission; votes are nullified), removes the matching review and
  # any YSWS review it generated, and resets the project to an un-shipped draft.
  # Used to fully un-stick a project that was shipped under the wrong kind.
  # Refuses to touch a paid-out ship.
  def clear_latest_ship
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :update?

    reason = params[:reason].to_s.strip
    ship_event = @project.last_ship_event

    if ship_event.nil?
      redirect_to admin_project_path(@project), alert: "This project has no ship to clear."
      return
    end

    if reason.blank?
      redirect_to admin_project_path(@project), alert: "Explain why the latest ship is being cleared."
      return
    end

    if ship_event.payout.present?
      redirect_to admin_project_path(@project),
                  alert: "Can't clear a ship that has already paid out. Resolve the payout first."
      return
    end

    old_status = @project.ship_status
    cleared = {
      "ship_event_id" => ship_event.id,
      "certification_status" => ship_event.certification_status,
      "votes_count" => ship_event.votes_count,
      "body" => ship_event.body
    }

    ApplicationRecord.transaction do
      review = @project.ship_reviews.order(created_at: :desc).first
      # YSWS reviews FK to both the ship event and its review with no cascade /
      # dependent, so clear them first or the destroys below hit InvalidForeignKey.
      ::Certification::Ysws.where(post_ship_event_id: ship_event.id).destroy_all
      ::Certification::Ysws.where(ship_cert_id: review.id).destroy_all if review
      review&.destroy!
      ship_event.destroy!
      remaining_latest = @project.ship_event_posts.maximum(:created_at)
      @project.update_columns(ship_status: "draft", shipped_at: remaining_latest)
    end

    log_admin_version("admin_clear_latest_ship",
      "ship_status" => [ old_status, "draft" ],
      "cleared_ship" => cleared,
      "reason" => reason)

    redirect_to admin_project_path(@project), notice: "Cleared the latest ship and reset the project to draft."
  end

  def sync_last_ship_event_certification(new_status)
    ship_event = @project.last_ship_event
    return unless ship_event

    new_cert = case new_status
    when "approved" then "approved"
    when "rejected" then "rejected"
    else "pending"
    end
    return if ship_event.certification_status == new_cert
    ship_event.update!(certification_status: new_cert)
  end

  def force_state
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :update?

    state_column = ::Project.aasm.attribute_name
    old_state = @project.send(state_column)
    new_state = params[:target_state]

    unless ::Project.aasm.states.map { |s| s.name.to_s }.include?(new_state)
      redirect_to admin_project_path(@project), alert: "Invalid state."
      return
    end

    if old_state == new_state
      redirect_to admin_project_path(@project), alert: "Project is already #{new_state}."
      return
    end

    @project.update_column(state_column, new_state)

    log_admin_version("update", state_column => [ old_state, new_state ])

    redirect_to admin_project_path(@project), notice: "State forced from #{old_state} to #{new_state}."
  end

  private

  # Records a staff action against @project in the PaperTrail audit log.
  def log_admin_version(event, object_changes)
    ::PaperTrail::Version.create!(
      item: @project,
      event: event,
      whodunnit: current_user.id.to_s,
      object_changes: object_changes
    )
  end

  def hardware_stage_label(stage)
    case stage
    when "design" then "Hardware - design"
    when "build" then "Hardware - build"
    else "Software"
    end
  end
end
