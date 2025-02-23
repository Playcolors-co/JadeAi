import React, { useState, useEffect } from 'react';
import {
  Box,
  Typography,
  Paper,
  Grid,
  List,
  ListItem,
  ListItemText,
  Divider,
  Tab,
  Tabs,
  CircularProgress,
  LinearProgress,
  Card,
  CardContent,
  IconButton,
  TextField,
  InputAdornment
} from '@mui/material';
import { Search, Refresh } from '@mui/icons-material';
import axios from 'axios';

interface TabPanelProps {
  children?: React.ReactNode;
  index: number;
  value: number;
}

function TabPanel(props: TabPanelProps) {
  const { children, value, index, ...other } = props;

  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`system-tabpanel-${index}`}
      aria-labelledby={`system-tab-${index}`}
      {...other}
    >
      {value === index && <Box sx={{ p: 3 }}>{children}</Box>}
    </div>
  );
}

interface SystemInfo {
  cpu: {
    model: string;
    cores: number;
    usage: number;
    temperature: number;
  };
  memory: {
    total: number;
    used: number;
    free: number;
  };
  gpu: {
    model: string;
    memory: {
      total: number;
      used: number;
    };
    temperature: number;
  };
  storage: {
    total: number;
    used: number;
    free: number;
  };
}

interface LogEntry {
  timestamp: string;
  level: 'info' | 'warning' | 'error';
  message: string;
  source: string;
}

const System: React.FC = () => {
  const [tabValue, setTabValue] = useState(0);
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchSystemInfo();
    fetchLogs();
    const interval = setInterval(fetchSystemInfo, 5000);
    return () => clearInterval(interval);
  }, []);

  const fetchSystemInfo = async () => {
    try {
      const response = await axios.get('http://localhost:5000/api/system/info');
      setSystemInfo(response.data);
      setLoading(false);
    } catch (error) {
      console.error('Error fetching system info:', error);
    }
  };

  const fetchLogs = async () => {
    try {
      const response = await axios.get('http://localhost:5000/api/system/logs');
      setLogs(response.data);
    } catch (error) {
      console.error('Error fetching logs:', error);
    }
  };

  const handleTabChange = (event: React.SyntheticEvent, newValue: number) => {
    setTabValue(newValue);
  };

  const formatBytes = (bytes: number) => {
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    if (bytes === 0) return '0 B';
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(2)} ${sizes[i]}`;
  };

  const filteredLogs = logs.filter(
    (log) =>
      log.message.toLowerCase().includes(searchQuery.toLowerCase()) ||
      log.source.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const getLogColor = (level: string) => {
    switch (level) {
      case 'error':
        return 'error.main';
      case 'warning':
        return 'warning.main';
      default:
        return 'text.primary';
    }
  };

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="400px">
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        System
      </Typography>
      <Box sx={{ borderBottom: 1, borderColor: 'divider' }}>
        <Tabs value={tabValue} onChange={handleTabChange}>
          <Tab label="Overview" />
          <Tab label="Logs" />
        </Tabs>
      </Box>

      <TabPanel value={tabValue} index={0}>
        <Grid container spacing={3}>
          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  CPU
                </Typography>
                <Typography variant="body2" color="text.secondary" gutterBottom>
                  {systemInfo?.cpu.model}
                </Typography>
                <Typography variant="body2">
                  Cores: {systemInfo?.cpu.cores}
                </Typography>
                <Box sx={{ mt: 2 }}>
                  <Typography variant="body2" gutterBottom>
                    Usage: {systemInfo?.cpu.usage}%
                  </Typography>
                  <LinearProgress
                    variant="determinate"
                    value={systemInfo?.cpu.usage || 0}
                    sx={{ mb: 1 }}
                  />
                  <Typography variant="body2">
                    Temperature: {systemInfo?.cpu.temperature}°C
                  </Typography>
                </Box>
              </CardContent>
            </Card>
          </Grid>

          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Memory
                </Typography>
                <Box sx={{ mt: 2 }}>
                  <Typography variant="body2" gutterBottom>
                    Used: {formatBytes(systemInfo?.memory.used || 0)} /{' '}
                    {formatBytes(systemInfo?.memory.total || 0)}
                  </Typography>
                  <LinearProgress
                    variant="determinate"
                    value={(systemInfo?.memory.used || 0) / (systemInfo?.memory.total || 1) * 100}
                    sx={{ mb: 1 }}
                  />
                </Box>
              </CardContent>
            </Card>
          </Grid>

          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  GPU
                </Typography>
                <Typography variant="body2" color="text.secondary" gutterBottom>
                  {systemInfo?.gpu.model}
                </Typography>
                <Box sx={{ mt: 2 }}>
                  <Typography variant="body2" gutterBottom>
                    Memory: {formatBytes(systemInfo?.gpu.memory.used || 0)} /{' '}
                    {formatBytes(systemInfo?.gpu.memory.total || 0)}
                  </Typography>
                  <LinearProgress
                    variant="determinate"
                    value={(systemInfo?.gpu.memory.used || 0) / (systemInfo?.gpu.memory.total || 1) * 100}
                    sx={{ mb: 1 }}
                  />
                  <Typography variant="body2">
                    Temperature: {systemInfo?.gpu.temperature}°C
                  </Typography>
                </Box>
              </CardContent>
            </Card>
          </Grid>

          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Storage
                </Typography>
                <Box sx={{ mt: 2 }}>
                  <Typography variant="body2" gutterBottom>
                    Used: {formatBytes(systemInfo?.storage.used || 0)} /{' '}
                    {formatBytes(systemInfo?.storage.total || 0)}
                  </Typography>
                  <LinearProgress
                    variant="determinate"
                    value={(systemInfo?.storage.used || 0) / (systemInfo?.storage.total || 1) * 100}
                    sx={{ mb: 1 }}
                  />
                </Box>
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      </TabPanel>

      <TabPanel value={tabValue} index={1}>
        <Box sx={{ mb: 2 }}>
          <TextField
            fullWidth
            placeholder="Search logs..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            InputProps={{
              startAdornment: (
                <InputAdornment position="start">
                  <Search />
                </InputAdornment>
              ),
              endAdornment: (
                <InputAdornment position="end">
                  <IconButton onClick={fetchLogs}>
                    <Refresh />
                  </IconButton>
                </InputAdornment>
              )
            }}
          />
        </Box>
        <Paper sx={{ maxHeight: 600, overflow: 'auto' }}>
          <List>
            {filteredLogs.map((log, index) => (
              <React.Fragment key={index}>
                <ListItem>
                  <ListItemText
                    primary={log.message}
                    secondary={`${log.timestamp} - ${log.source}`}
                    sx={{ color: getLogColor(log.level) }}
                  />
                </ListItem>
                {index < filteredLogs.length - 1 && <Divider />}
              </React.Fragment>
            ))}
          </List>
        </Paper>
      </TabPanel>
    </Box>
  );
};

export default System;
