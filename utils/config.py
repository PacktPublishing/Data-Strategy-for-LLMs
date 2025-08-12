import os
from pathlib import Path
from dotenv import load_dotenv

def load_api_keys():
    """
    Load API keys from .env file in the repository root.
    
    This function searches for a .env file starting from the current directory
    and moving up to parent directories until it finds the repository root.
    
    Returns:
        dict: Dictionary containing API keys and configuration
    """
    # Find the repository root by looking for .env file
    current_path = Path.cwd()
    env_path = None
    
    # Search up the directory tree for .env file
    for parent in [current_path] + list(current_path.parents):
        potential_env = parent / '.env'
        if potential_env.exists():
            env_path = potential_env
            break
    
    # If no .env found, try the utils parent directory (repo root)
    if env_path is None:
        repo_root = Path(__file__).parent.parent
        env_path = repo_root / '.env'
    
    # Load environment variables
    if env_path and env_path.exists():
        load_dotenv(env_path)
    
    return {
        'openai_api_key': os.getenv('OPENAI_API_KEY'),
        'anthropic_api_key': os.getenv('ANTHROPIC_API_KEY'),
        'openrouter_api_key': os.getenv('OPENROUTER_API_KEY'),
        'env_file_path': str(env_path) if env_path else None
    }

def get_openai_api_key():
    """Get OpenAI API key from environment."""
    config = load_api_keys()
    api_key = config['openai_api_key']
    
    if not api_key:
        raise ValueError(
            "OpenAI API key not found. Please:\n"
            "1. Create a .env file in the repository root\n"
            "2. Add: OPENAI_API_KEY=your-api-key-here\n"
            "3. Restart your notebook kernel"
        )
    
    return api_key

def get_openrouter_api_key():
    """Get OpenRouter API key from environment."""
    config = load_api_keys()
    api_key = config['openrouter_api_key']
    
    if not api_key:
        raise ValueError(
            "OpenRouter API key not found. Please:\n"
            "1. Create a .env file in the repository root\n"
            "2. Add: OPENROUTER_API_KEY=your-api-key-here\n"
            "3. Restart your notebook kernel"
        )
    
    return api_key
