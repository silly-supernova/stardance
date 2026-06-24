class Admin::Certification::DevlogCommitsPolicy < ApplicationPolicy
  def index?
    return false unless user&.can_review_ysws?
    # record is a Post::Devlog; confine reviewers to their own category so a
    # Hardware GOI can't pull commits for a software project (and vice versa).
    user.can_review_project_category?(record.try(:post)&.project)
  end
end
