class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "SceneFoundry <orders@scenefoundry.local>") }
  layout "mailer"
end
