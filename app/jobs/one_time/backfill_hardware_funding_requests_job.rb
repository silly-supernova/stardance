# frozen_string_literal: true

# Pulls legacy hardware projects into the funding review queue.
#
# The queue is a list of Certification::FundingRequest rows, so a project only
# shows up once it has a pending request. Projects from before the queue existed
# never got to submit one. This job creates a pending request for each eligible
# legacy hardware project so reviewers can act on them.
#
# RUN OneTime::BackfillHardwareStageJob FIRST. That job (audited, dry-run by
# default) promotes AI-typed hardware projects from hardware_stage = nil to the
# "design" entry stage. This job deliberately does NOT touch hardware_stage — it
# only acts on projects already sitting in "design", which is exactly the set the
# stage job produces. Keeping the stage flip in one place preserves its audit
# trail and the devlog-phase warnings documented there.
#
# DRY RUN BY DEFAULT: logs the candidate ids and writes nothing. Pass
# dry_run: false to persist. Always dry-run first and eyeball the list.
#
# The owner never picked a tier or dollar amount, so each request is seeded with
# a placeholder — tier B and $0 requested — and internal_reason records that it
# was backfilled. The seeded request just means "this needs a funding decision";
# the reviewer sets the real tier and amount on approval.
#
# Writes go through save(validate: false) to bypass the create guards (design
# stage / has-devlogs / no-pending) — this backfill intentionally forces these
# projects into the queue. PaperTrail (audit) still fires and is attributed to
# this job via PaperTrail.request.
#
# Idempotent: the scope excludes any project that already has a funding request,
# so re-running won't create duplicates.
class OneTime::BackfillHardwareFundingRequestsJob < ApplicationJob
  queue_as :literally_whenever

  WHODUNNIT = "OneTime::BackfillHardwareFundingRequestsJob"

  # Tier B — the smallest tier; reviewers bump it when they set the real amount.
  BACKFILL_TIER = 1

  # AI-typed hardware projects already promoted into the design stage (by
  # BackfillHardwareStageJob) that have never had a funding request.
  def scope
    Project.where(project_type: "Hardware", hardware_stage: "design", deleted_at: nil)
           .where.not(id: Certification::FundingRequest.select(:project_id))
  end

  def perform(dry_run: true)
    candidates = scope.to_a
    ownerless, eligible = candidates.partition { |p| p.memberships.owner.first&.user.nil? }

    if dry_run
      Rails.logger.info "[BackfillHardwareFundingRequests] DRY RUN — would create #{eligible.size} " \
                        "funding request(s): #{eligible.map(&:id).inspect}"
      Rails.logger.warn "[BackfillHardwareFundingRequests] DRY RUN — skipping #{ownerless.size} " \
                        "ownerless project(s): #{ownerless.map(&:id).inspect}" if ownerless.any?
      return eligible.map(&:id)
    end

    created = 0
    skipped = ownerless.size
    PaperTrail.request(whodunnit: WHODUNNIT) do
      eligible.each do |project|
        owner = project.memberships.owner.first.user
        request = project.certification_funding_requests.new(
          user: owner,
          complexity_tier: BACKFILL_TIER,
          requested_amount_cents: 0,
          status: :pending,
          internal_reason: "Backfilled: legacy hardware project from before the funding queue. " \
                           "Owner never submitted a tier or amount — set the real tier and amount on approval."
        )
        request.save!(validate: false)
        created += 1
      rescue ActiveRecord::RecordNotUnique
        # A pending request already exists (raced or partial prior run); leave it.
        skipped += 1
      end
    end

    Rails.logger.info "[BackfillHardwareFundingRequests] Created #{created} funding request(s), skipped #{skipped}"
    created
  end
end
