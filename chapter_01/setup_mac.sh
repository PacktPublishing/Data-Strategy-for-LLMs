#!/bin/bash

# macOS Development Environment Setup Script
# This script automates the setup process for the 'Data Strategy for LLMs' book project.

# --- Color Codes for Output ---
echo_info() {
    echo -e "\033[1;34m$1\033[0m"
}
echo_success() {
    echo -e "\033[1;32m$1\033[0m"
}
echo_error() {
    echo -e "\033[1;31m$1\033[0m"
}

# --- Step 1: Check for and Install Homebrew ---
echo_info "Checking for Homebrew..."
if ! command -v brew &> /dev/null
then
    echo_info "Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ $? -ne 0 ]; then
        echo_error "Homebrew installation failed. Please install it manually and re-run this script."
        exit 1
    fi
else
    echo_success "Homebrew is already installed."
fi

# --- Step 2: Check for and Install Python 3 ---
echo_info "Checking for Python 3..."
if ! brew list python@3 &> /dev/null
then
    echo_info "Python 3 not found. Installing Python 3 via Homebrew..."
    brew install python@3
    if [ $? -ne 0 ]; then
        echo_error "Python 3 installation failed. Please try installing it manually."
        exit 1
    fi
else
    echo_success "Python 3 is already installed."
fi

# --- Step 3: Create a Python Virtual Environment ---
# --- Step 3: Create a Python Virtual Environment in the Project Root ---
# Navigate to the parent directory (project root)
cd ..

PROJECT_DIR="llm-data-book"
echo_info "Setting up project directory and virtual environment..."

if [ ! -d "$PROJECT_DIR" ]; then
    mkdir "$PROJECT_DIR"
    echo_info "Created project directory: $PROJECT_DIR"
fi

cd "$PROJECT_DIR"

if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo_info "Created virtual environment in '$PROJECT_DIR/venv'"
else
    echo_success "Virtual environment already exists."
fi

# --- Step 4: Activate Virtual Environment and Install Packages ---
source venv/bin/activate

echo_info "Installing required Python packages from requirements.txt..."

# Copy requirements.txt from the Jupyter Notebooks directory
if [ -f "../chapter_01/requirements.txt" ]; then
    cp "../chapter_01/requirements.txt" .
fi

pip install -r requirements.txt

if [ $? -ne 0 ]; then
    echo_error "Failed to install Python packages. Please check requirements.txt and your internet connection."
    deactivate
    exit 1
fi

echo_success "All packages installed successfully."

# --- Final Instructions ---
deactivate
echo_success "\nSetup complete!"
echo_info "To get started, navigate to the project directory and activate the virtual environment:"
echo_info "  cd $PROJECT_DIR"
echo_info "  source venv/bin/activate"
