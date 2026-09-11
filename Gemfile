source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.0"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
gem "rexml", ">= 3.3"
gem "pg", "~> 1.5"
gem "bcrypt", "~> 3.1"
gem "stripe", "~> 15.0"
gem "aws-sdk-s3", "~> 1.0", require: false

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# The Vite development server proxies /api to Rails, so this prototype does
# not need a permissive CORS dependency.

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
end
