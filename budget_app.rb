require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "yaml"
require "psych"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, 'super secret'
  set :erb, escape_html: true
end

helpers do
  def current_month
    time = Time.new
    time.strftime("%Y-%m")
  end
end

before do
  reset_session_filter if session[:filter].nil?
end

def reset_session_filter
  session[:filter] = [current_month, "any"]
end

def data_path
  File.expand_path("../data", __FILE__)
end

def transaction_file_path
  data_path + "/" + session[:username] + ".yml"
end

def load_transaction_file
  YAML.load_file(transaction_file_path)
end

def credentials_path
  File.expand_path("../users.yml", __FILE__)
end

def load_user_credentials
  path = credentials_path
  YAML.load_file(path)
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username][:pass])
    bcrypt_password == password
  else
    false
  end
end

def store_user_data(username, password, first_name, last_name, email)
  data = load_user_credentials
  data[username] = {
    pass: password.to_s,
    first_name: first_name,
    last_name: last_name,
    email: email
  }
  File.write(credentials_path, YAML.dump(data))
end

def create_transactions_file(username)
  file_path = data_path + "/" + username + ".yml"
  File.new(file_path, "w+")
  File.open(file_path, "w") do |file|
    file.write(Psych.dump({}))
  end
end

def check_data(username, email, credentials)
  if credentials.keys.include?(username)
    session[:message] = "Username taken"
    redirect "/signup"
  elsif credentials.find { |_, data| data[:email] == email }
    session[:message] = "Email taken"
    redirect "/signup"
  end
end

def user_signed_in?
  session.key?(:username)
end

def redirect_unless_signed_in
  redirect "/" unless user_signed_in?
end

def calculate_date
  time = Time.new
  time.strftime("%Y-%m-%d")
end

def store_data(data, key, input_data)
  data[key] = {
    kind: input_data[0],
    date: input_data[1],
    amount: input_data[2],
    category: input_data[3],
    comment: input_data[4]
  }
  data
end

def store_transaction_data(input_data)
  time = Time.new
  time = time.strftime("%Y-%m-%d_%H:%M:%S")
  data = load_transaction_file
  data = store_data(data, time, input_data)
  File.write(transaction_file_path, YAML.dump(data))
end

def store_edited_data(input_data, id)
  if input_data[0].empty?
    session[:message] = "Please choose the kind of transaction"
    redirect "/edit/#{id}"
  end
  data = load_transaction_file
  data = store_data(data, id, input_data)
  File.write(transaction_file_path, YAML.dump(data))
end

def count_balance
  data = load_transaction_file
  data.map { |_, transaction| transaction }.inject(0) do |sum, transaction|
    if transaction[:kind].eql?("income")
      sum += transaction[:amount]
    elsif transaction[:kind].eql?("expense")
      sum -= transaction[:amount]
    end
  end
end

def find_last_transactions(transactions)
  sorted_keys = transactions.keys.sort.reverse[0..4]
  sorted_keys.map { |key| transactions[key] }
end

def filter_by_year(transactions)
  year = session[:filter][0]
  transactions.select { |_, transaction| transaction[:date][0..3] == year }
end

def filter_by_month(transactions)
  month = session[:filter][0]
  transactions.select { |_, transaction| transaction[:date][0..6] == month }
end

def filter_by_date(transactions)
  return transactions if session[:filter].nil?
  if session[:filter][0].length == 4
    filter_by_year(transactions)
  else
    filter_by_month(transactions)
  end
end

def filter_by_category(transactions)
  return transactions if session[:filter][1].eql? "any"
  category = session[:filter][1]
  transactions.select { |_, transaction| transaction[:category] == category }
end

def sort_transactions(transactions)
  transactions.sort_by { |k| k[1][:date] }
end

def filter_transaction
  transactions = load_transaction_file
  date_filtered = filter_by_date(transactions)
  category_filtered = filter_by_category(date_filtered)
  sort_transactions(category_filtered)
end

get "/" do
  if user_signed_in?
    transactions = load_transaction_file
    @last_transactions = find_last_transactions(transactions)
    @balance = count_balance
    erb :index
  else
    erb :signin
  end
end

post "/signin" do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = params[:username]
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid credentials!"
    status 422
    erb :signin
  end
end

get "/signup" do
  redirect "/" if user_signed_in?
  erb :signup
end

post "/signup" do
  username = params[:username]
  first_name = params[:first_name]
  last_name = params[:last_name]
  email = params[:email]
  credentials = load_user_credentials
  check_data(username, email, credentials)
  password = BCrypt::Password.create(params[:password])
  store_user_data(username, password, first_name, last_name, email)
  create_transactions_file(username)
  session[:message] = "New account created"
  redirect "/"
end

get "/new" do
  redirect_unless_signed_in
  @date = calculate_date
  erb :new
end

post "/new" do
  input_data = [
    params[:kind].to_s,
    params[:date],
    params[:amount].to_i,
    params[:category].to_s,
    params[:comment]
  ]
  store_transaction_data(input_data)
  session[:message] = "New transaction added!"
  redirect "/"
end

get "/history" do
  redirect_unless_signed_in
  @transactions_list = filter_transaction
  reset_session_filter
  erb :history
end

post "/history" do
  range = params[:range] == "year" ? params[:year] : params[:month]
  session[:filter] = [range, params[:category]]
  redirect "/history"
end

get "/delete/:id" do
  data = load_transaction_file
  data.delete_if { |name, _| name == params[:id] }
  File.write(transaction_file_path, YAML.dump(data))
  redirect "/history"
end

get "/edit/:id" do
  redirect_unless_signed_in
  data = load_transaction_file
  @id = params[:id]
  @date = data[@id][:date]
  @amount = data[@id][:amount]
  @comment = data[@id][:comment]
  erb :edit
end

post "/edit/:id" do
  input_data = [
    params[:kind].to_s,
    params[:date],
    params[:amount].to_i,
    params[:category].to_s,
    params[:comment]
  ]
  store_edited_data(input_data, params[:id])
  session[:message] = "Transaction edited!"
  redirect "/history"
end

get "/logout" do
  session.delete(:username)
  redirect "/"
end
