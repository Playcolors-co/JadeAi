# Jade AI Deployment System

A robust deployment system for Jade AI components with standardized output formatting, comprehensive error handling, and automated testing.

## Features

- Standardized console output with color-coded messages and progress tracking
- Component-based architecture with Docker support
- Comprehensive error handling and logging
- Automated deployment and rollback testing
- Multi-language support through JSON message files
- YAML/JSON configuration support

## Requirements

- Python 3.8+
- Docker 20.10+
- See `requirements.txt` for Python dependencies

## System Requirements

- Disk Space: 5GB minimum
- Memory: 2GB minimum
- CPU: 2 cores minimum
- Internet connectivity for package installation

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/jadeai.git
cd jadeai
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Install system dependencies:
```bash
./scripts/system_setup.sh
```

## Usage

### Basic Deployment

Deploy to a remote host:
```bash
./deploy.sh --host <hostname> --user <username> --pass <password>
```

### Options

- `--host`: Remote host address (default: 192.168.88.59)
- `--user`: Remote username (default: theboxpi)
- `--pass`: Remote password
- `--dir`: Remote installation directory (default: /opt/jadeai)

### Components

The system includes the following components:

1. System Check
   - System requirements check
   - System update

2. System configuration
   - Base system update
   - Configure bluetooth to be used as Device (Single HID mouse/keyboard device) and client
   - HDMI to USB device conficuration for input video streaming 
   - Install Docker
   - Standard Directory structure creation

3. Portainer
   - Install Portainer container on Docker 

3. Web Site
   - Install the admin web site as container on Docker 

## Configuration

### Directory Structure

```
jadeai/
├── config/                     # Configuration files
│   ├── *.yaml                 # Component configurations
│   └── *_en.json              # Localized messages
├── scripts/                   # Deployment scripts
│   ├── common.sh             # Common functions
│   ├── deploy.sh             # Main deployment script
│   └── *_setup.sh           # Component setup scripts
├── tests/                    # Test scripts
│   ├── *_deploy_test.sh     # Deployment tests
│   └── *_rollback_test.sh   # Rollback tests
└── logs/                     # Log files
```

### Message Format

Messages are stored in JSON files with the following structure:
```json
{
  "component": {
    "info": {
      "key": "Message with {0} parameter"
    },
    "warn": {
      "key": "[WARN] Warning message"
    },
    "error": {
      "key": "[ERROR] Error message"
    }
  }
}
```

### Console Out and Progress Tracking
Those are the colors scheme of console messagges 
Report each info message with [INFO] in green at begginign of any row
Report each info message with [WARN] in YELLOW at begginign of any row
Report each info message with [ERROR] in RED at begginign of any row

## Testing

Run deployment tests:
```bash
./tests/system_deploy_test.sh
```

Run rollback tests:
```bash
./tests/system_rollback_test.sh
```

## Error Handling

The system provides comprehensive error handling:
- Color-coded error messages
- Detailed error logging
- Automatic retry for transient failures
- Rollback on critical errors

## Logging

Logs are stored in the `logs` directory with the maximux verbosity availabke.
This is the log the format:
```
logs/
├── deploy.log
└── component.log
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
