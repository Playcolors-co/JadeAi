import React, { useState, useEffect } from 'react';
import {
  Box,
  Typography,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Chip,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem
} from '@mui/material';
import axios from 'axios';

interface Model {
  id: string;
  name: string;
  type: 'local' | 'cloud';
  status: 'active' | 'installed' | 'available';
}

const Models: React.FC = () => {
  const [models, setModels] = useState<Model[]>([]);
  const [open, setOpen] = useState(false);
  const [selectedModel, setSelectedModel] = useState<Model | null>(null);
  const [configForm, setConfigForm] = useState({
    name: '',
    type: 'local',
    apiKey: ''
  });

  useEffect(() => {
    fetchModels();
  }, []);

  const fetchModels = async () => {
    try {
      const response = await axios.get('http://localhost:5000/api/models');
      setModels(response.data);
    } catch (error) {
      console.error('Error fetching models:', error);
    }
  };

  const handleConfigOpen = (model: Model) => {
    setSelectedModel(model);
    setConfigForm({
      name: model.name,
      type: model.type,
      apiKey: ''
    });
    setOpen(true);
  };

  const handleConfigClose = () => {
    setOpen(false);
    setSelectedModel(null);
  };

  const handleConfigSave = async () => {
    try {
      await axios.post('http://localhost:5000/api/config', {
        model: selectedModel?.id,
        ...configForm
      });
      handleConfigClose();
      fetchModels();
    } catch (error) {
      console.error('Error saving configuration:', error);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active':
        return 'success';
      case 'installed':
        return 'info';
      default:
        return 'default';
    }
  };

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        AI Models
      </Typography>
      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>Name</TableCell>
              <TableCell>Type</TableCell>
              <TableCell>Status</TableCell>
              <TableCell>Actions</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {models.map((model) => (
              <TableRow key={model.id}>
                <TableCell>{model.name}</TableCell>
                <TableCell>
                  <Chip
                    label={model.type}
                    color={model.type === 'local' ? 'primary' : 'secondary'}
                    size="small"
                  />
                </TableCell>
                <TableCell>
                  <Chip
                    label={model.status}
                    color={getStatusColor(model.status) as any}
                    size="small"
                  />
                </TableCell>
                <TableCell>
                  <Button
                    variant="outlined"
                    size="small"
                    onClick={() => handleConfigOpen(model)}
                  >
                    Configure
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>

      <Dialog open={open} onClose={handleConfigClose}>
        <DialogTitle>Configure {selectedModel?.name}</DialogTitle>
        <DialogContent>
          <Box sx={{ pt: 2 }}>
            <FormControl fullWidth sx={{ mb: 2 }}>
              <InputLabel>Type</InputLabel>
              <Select
                value={configForm.type}
                label="Type"
                onChange={(e) => setConfigForm({ ...configForm, type: e.target.value as 'local' | 'cloud' })}
              >
                <MenuItem value="local">Local</MenuItem>
                <MenuItem value="cloud">Cloud</MenuItem>
              </Select>
            </FormControl>
            {configForm.type === 'cloud' && (
              <TextField
                fullWidth
                label="API Key"
                type="password"
                value={configForm.apiKey}
                onChange={(e) => setConfigForm({ ...configForm, apiKey: e.target.value })}
                sx={{ mb: 2 }}
              />
            )}
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleConfigClose}>Cancel</Button>
          <Button onClick={handleConfigSave} variant="contained">
            Save
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default Models;
