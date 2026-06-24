class Admin::Certification::DevlogPolicy < ApplicationPolicy
  def update?
    return false unless user&.can_review_ysws?
    # record is a Certification::Devlog (devlog review); confine reviewers to
    # their own category so a Hardware GOI can't edit a software project's
    # devlog verdicts (and vice versa).
    user.can_review_project_category?(record.try(:ysws_review)&.project)
  end
end
