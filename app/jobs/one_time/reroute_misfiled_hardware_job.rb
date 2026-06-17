# frozen_string_literal: true

# Reroutes hardware projects that got mis-filed into the software ship review
# queue. The AI type classifier (Project::TypeCheckJob, which runs at ship time)
# marks these project_type == "Hardware"; some also sit at hardware_stage
# "design". Hardware is judged in the funding queue, not peer ship review, so
# rather than have a reviewer reject them — which dings the rejection rate and
# pays a review bounty for no real work — this job:
#
#   1. deletes the stuck pending Certification::Ship review. No verdict, so no
#      rejection and no bounty, and it frees the one-pending-review-per-project
#      slot (a unique index) so the owner can reship later through the hardware
#      flow; and
#   2. DMs the owner to switch the project to Hardware in settings and submit
#      their design for funding.
#
# It does NOT flip hardware_stage — the AI can be wrong, so the owner confirms by
# switching it themselves in project settings.
#
# DRY RUN BY DEFAULT: logs the affected review ids and writes nothing. Pass
# dry_run: false to act. Idempotent: once a review is deleted its project falls
# out of scope, so re-running won't re-notify.
#
# Deletes go through PaperTrail.request so the audit version is attributed here.
class OneTime::RerouteMisfiledHardwareJob < ApplicationJob
  queue_as :literally_whenever

  WHODUNNIT = "OneTime::RerouteMisfiledHardwareJob"

  # Pending ship reviews whose project is hardware (design-stage or AI-typed) —
  # exactly the set Certification::Ship.software_only hides from reviewers.
  def scope
    Certification::Ship
      .where(status: :pending)
      .joins(:project)
      .where(projects: { deleted_at: nil })
      .where("projects.hardware_stage = 'design' OR projects.project_type = 'Hardware'")
  end

  def perform(dry_run: true)
    reviews = scope.includes(project: { memberships: :user }).to_a

    if dry_run
      Rails.logger.info "[RerouteMisfiledHardware] DRY RUN — would reroute #{reviews.size} " \
                        "ship review(s): #{reviews.map(&:id).inspect}"
      return reviews.map(&:id)
    end

    rerouted = 0
    PaperTrail.request(whodunnit: WHODUNNIT) do
      reviews.each do |review|
        project = review.project
        review.destroy!
        notify_owner(project)
        rerouted += 1
      end
    end

    Rails.logger.info "[RerouteMisfiledHardware] Rerouted #{rerouted} ship review(s) out of the software queue"
    rerouted
  end

  private

  def notify_owner(project)
    owner = project.memberships.owner.first&.user
    return unless owner&.slack_id.present?

    owner.dm_user(
      "Heads up! '#{project.title}' looks like a hardware project, and hardware goes through a " \
      "different path than software. We've taken it out of the ship review queue — to keep going, open " \
      "your project settings, switch it to Hardware, and submit your design to request funding."
    )
  end
end
