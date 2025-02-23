import React, { useState, useEffect } from 'react';
import {
  Box,
  Typography,
  Paper,
  Grid,
  TextField,
  Button,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Alert,
  Snackbar,
  Switch,
  FormControlLabel
} from '@mui/material';
import axios from 'axios';

interface Config {
  ai_backend: string;
  api_keys: {
    openai: string;
    anthropic: string;
  };
  system_settings: {
    voice_commands: boolean;
    auto_suggestions: boolean;
    performance_mode: 'balanced' | 'performance' | 'power-saving';
  };
}

const Settings: React.FC = () => {
  const [config, setConfig] = useState<Config>({
    ai_backend: 'local',
    api_keys: {
      openai: '',
      anthropic: ''
    },
    system_settings: {
      voice_commands: true,
      auto_suggestions: true,
      performance_mode: 'balanced'
    }
  });

  const [snackbar, setSnackbar] = useState({
    open: false,
    message: '',
    severity: 'success' as 'success' | 'error'
  });

  useEffect(() => {
    fetchConfig();
  }, []);

  const fetchConfig = async () => {
    try {
      const response = await axios.get('http://localhost:5000/api/config');
      setConfig(response.data);
    } catch (error) {
      console.error('Error fetching configuration:', error);
      setSnackbar({
        open: true,
        message: 'Error loading configuration',
        severity: 'error'
      });
    }
  };

  const handleSave = async () => {
    try {
      await axios.post('http://localhost:5000/api/config', config);
      setSnackbar({
        open: true,
        message: 'Settings saved successfully',
        severity: 'success'
      });
    } catch (error) {
      console.error('Error saving configuration:', error);
      setSnackbar({
        open: true,
        message: 'Error saving configuration',
        severity: 'error'
      });
    }
  };

  const handleCloseSnackbar = () => {
    setSnackbar({ ...snackbar, open: false });
  };

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        Settings
      </Typography>
      <Paper sx={{ p: 3 }}>
        <Grid container spacing={3}>
          <Grid item xs={12}>
            <Typography variant="h6" gutterBottom>
              AI Configuration
            </Typography>
            <FormControl fullWidth sx={{ mb: 2 }}>
              <InputLabel>AI Backend</InputLabel>
              <Select
                value={config.ai_backend}
                label="AI Backend"
                onChange={(e) => setConfig({ ...config, ai_backend: e.target.value })}
              >
                <MenuItem value="local">Local Models</MenuItem>
                <MenuItem value="cloud">Cloud APIs</MenuItem>
                <MenuItem value="hybrid">Hybrid (Local + Cloud)</MenuItem>
              </Select>
            </FormControl>
          </Grid>

          <Grid item xs={12}>
            <Typography variant="h6" gutterBottom>
              API Keys
            </Typography>
            <Grid container spacing={2}>
              <Grid item xs={12} md={6}>
                <TextField
                  fullWidth
                  label="OpenAI API Key"
                  type="password"
                  value={config.api_keys.openai}
                  onChange={(e) =>
                    setConfig({
                      ...config,
                      api_keys: { ...config.api_keys, openai: e.target.value }
                    })
                  }
                />
              </Grid>
              <Grid item xs={12} md={6}>
                <TextField
                  fullWidth
                  label="Anthropic API Key"
                  type="password"
                  value={config.api_keys.anthropic}
                  onChange={(e) =>
                    setConfig({
                      ...config,
                      api_keys: { ...config.api_keys, anthropic: e.target.value }
                    })
                  }
                />
              </Grid>
            </Grid>
          </Grid>

          <Grid item xs={12}>
            <Typography variant="h6" gutterBottom>
              System Settings
            </Typography>
            <Grid container spacing={2}>
              <Grid item xs={12} md={6}>
                <FormControlLabel
                  control={
                    <Switch
                      checked={config.system_settings.voice_commands}
                      onChange={(e) =>
                        setConfig({
                          ...config,
                          system_settings: {
                            ...config.system_settings,
                            voice_commands: e.target.checked
                          }
                        })
                      }
                    />
                  }
                  label="Voice Commands"
                />
              </Grid>
              <Grid item xs={12} md={6}>
                <FormControlLabel
                  control={
                    <Switch
                      checked={config.system_settings.auto_suggestions}
                      onChange={(e) =>
                        setConfig({
                          ...config,
                          system_settings: {
                            ...config.system_settings,
                            auto_suggestions: e.target.checked
                          }
                        })
                      }
                    />
                  }
                  label="AI Suggestions"
                />
              </Grid>
              <Grid item xs={12}>
                <FormControl fullWidth>
                  <InputLabel>Performance Mode</InputLabel>
                  <Select
                    value={config.system_settings.performance_mode}
                    label="Performance Mode"
                    onChange={(e) =>
                      setConfig({
                        ...config,
                        system_settings: {
                          ...config.system_settings,
                          performance_mode: e.target.value as 'balanced' | 'performance' | 'power-saving'
                        }
                      })
                    }
                  >
                    <MenuItem value="balanced">Balanced</MenuItem>
                    <MenuItem value="performance">High Performance</MenuItem>
                    <MenuItem value="power-saving">Power Saving</MenuItem>
                  </Select>
                </FormControl>
              </Grid>
            </Grid>
          </Grid>

          <Grid item xs={12}>
            <Box display="flex" justifyContent="flex-end">
              <Button variant="contained" onClick={handleSave}>
                Save Settings
              </Button>
            </Box>
          </Grid>
        </Grid>
      </Paper>

      <Snackbar
        open={snackbar.open}
        autoHideDuration={6000}
        onClose={handleCloseSnackbar}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}
      >
        <Alert onClose={handleCloseSnackbar} severity={snackbar.severity}>
          {snackbar.message}
        </Alert>
      </Snackbar>
    </Box>
  );
};

export default Settings;
