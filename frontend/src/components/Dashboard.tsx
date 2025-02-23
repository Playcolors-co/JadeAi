import React, { useEffect, useState } from 'react';
import { Grid, Paper, Typography, Box, CircularProgress } from '@mui/material';
import { Line } from 'react-chartjs-2';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
} from 'chart.js';
import io from 'socket.io-client';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
);

interface SystemStats {
  cpu_usage: number;
  memory_usage: number;
  gpu_usage: number;
  active_model: string;
  requests_per_minute: number;
}

const Dashboard: React.FC = () => {
  const [stats, setStats] = useState<SystemStats>({
    cpu_usage: 0,
    memory_usage: 0,
    gpu_usage: 0,
    active_model: '',
    requests_per_minute: 0
  });

  const [chartData, setChartData] = useState({
    labels: [] as string[],
    datasets: [
      {
        label: 'CPU Usage',
        data: [] as number[],
        borderColor: 'rgb(75, 192, 192)',
        tension: 0.1
      },
      {
        label: 'Memory Usage',
        data: [] as number[],
        borderColor: 'rgb(255, 99, 132)',
        tension: 0.1
      },
      {
        label: 'GPU Usage',
        data: [] as number[],
        borderColor: 'rgb(54, 162, 235)',
        tension: 0.1
      }
    ]
  });

  useEffect(() => {
    const socket = io('http://localhost:5000');

    socket.on('system_stats', (newStats: SystemStats) => {
      setStats(newStats);
      
      const now = new Date().toLocaleTimeString();
      setChartData(prevData => {
        const labels = [...prevData.labels, now].slice(-10);
        const newData = prevData.datasets.map((dataset, index) => ({
          ...dataset,
          data: [...dataset.data, [newStats.cpu_usage, newStats.memory_usage, newStats.gpu_usage][index]].slice(-10)
        }));
        return { labels, datasets: newData };
      });
    });

    return () => {
      socket.disconnect();
    };
  }, []);

  const StatCard: React.FC<{ title: string; value: number | string }> = ({ title, value }) => (
    <Paper sx={{ p: 2, height: '100%' }}>
      <Typography variant="h6" gutterBottom>
        {title}
      </Typography>
      <Box display="flex" alignItems="center" justifyContent="center">
        {typeof value === 'number' ? (
          <Box position="relative" display="inline-flex">
            <CircularProgress variant="determinate" value={value} size={80} />
            <Box
              sx={{
                top: 0,
                left: 0,
                bottom: 0,
                right: 0,
                position: 'absolute',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <Typography variant="caption" component="div" color="text.secondary">
                {`${Math.round(value)}%`}
              </Typography>
            </Box>
          </Box>
        ) : (
          <Typography variant="h4">{value}</Typography>
        )}
      </Box>
    </Paper>
  );

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        System Dashboard
      </Typography>
      <Grid container spacing={3}>
        <Grid item xs={12} md={3}>
          <StatCard title="CPU Usage" value={stats.cpu_usage} />
        </Grid>
        <Grid item xs={12} md={3}>
          <StatCard title="Memory Usage" value={stats.memory_usage} />
        </Grid>
        <Grid item xs={12} md={3}>
          <StatCard title="GPU Usage" value={stats.gpu_usage} />
        </Grid>
        <Grid item xs={12} md={3}>
          <StatCard title="Active Model" value={stats.active_model} />
        </Grid>
        <Grid item xs={12}>
          <Paper sx={{ p: 2 }}>
            <Typography variant="h6" gutterBottom>
              System Performance
            </Typography>
            <Line data={chartData} options={{ maintainAspectRatio: false }} height={300} />
          </Paper>
        </Grid>
      </Grid>
    </Box>
  );
};

export default Dashboard;
