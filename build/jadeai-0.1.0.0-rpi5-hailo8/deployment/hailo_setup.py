#!/usr/bin/env python3
import hailo
import os
import sys
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MODELS_DIR = Path("/opt/jadeai/models")
HEF_DIR = MODELS_DIR / "hailo"

def setup_hailo():
    """Initialize and configure Hailo-8 device"""
    try:
        # Create device
        device = hailo.Device.create()
        logger.info(f"Created Hailo device successfully")

        # Get device info
        info = device.device_info()
        logger.info(f"Device ID: {info.id}")
        logger.info(f"Device Architecture: {info.arch}")
        
        # Configure power mode
        device.configure_power_mode(hailo.POWER_MODE_ULTRA_PERFORMANCE)
        logger.info("Configured power mode to ULTRA_PERFORMANCE")

        # Load and configure default models
        configure_models(device)

        return True

    except hailo.HailoException as e:
        logger.error(f"Failed to initialize Hailo device: {e}")
        return False

def configure_models(device):
    """Load and configure AI models on the Hailo device"""
    try:
        HEF_DIR.mkdir(parents=True, exist_ok=True)
        
        # Configure YOLOv8 for object detection
        yolo_hef = HEF_DIR / "yolov8.hef"
        if yolo_hef.exists():
            configure_network(device, yolo_hef, "yolov8")
            logger.info("Configured YOLOv8 model successfully")

        # Configure other models as needed
        # Add configuration for LLMs, speech processing, etc.

    except Exception as e:
        logger.error(f"Failed to configure models: {e}")
        raise

def configure_network(device, hef_path, name):
    """Configure a specific network on the device"""
    try:
        # Create network group from HEF file
        network_group = device.create_network_group(hef_path)
        
        # Configure network parameters
        network_group.network_config_params = {
            'batch_size': 1,
            'power_mode': hailo.POWER_MODE_ULTRA_PERFORMANCE
        }
        
        # Activate network
        network_group.activate()
        logger.info(f"Configured network {name} successfully")

    except hailo.HailoException as e:
        logger.error(f"Failed to configure network {name}: {e}")
        raise

if __name__ == "__main__":
    if not setup_hailo():
        sys.exit(1)
    logger.info("Hailo-8 setup completed successfully")
